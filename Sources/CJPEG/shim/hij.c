#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "jpeglib.h"
#include "jerror.h"
#include "transupp.h"
#include "../include/CJPEG.h"

/* libjpeg reports errors through exit() by default; jump back to the caller instead. */
typedef struct {
    struct jpeg_error_mgr base;
    jmp_buf jump;
} HIJError;

static void hij_error_exit(j_common_ptr cinfo) {
    longjmp(((HIJError *)cinfo->err)->jump, 1);
}

static void hij_silent(j_common_ptr cinfo, int level) {
    (void)cinfo;
    (void)level;
}

static void hij_install_errors(HIJError *err) {
    jpeg_std_error(&err->base);
    err->base.error_exit = hij_error_exit;
    err->base.emit_message = hij_silent;
}

/* Growable memory destination we own, so a failed encode can always free its buffer
   (libjpeg's jpeg_mem_dest leaves a dangling *outbuffer after it reallocates). */
typedef struct {
    struct jpeg_destination_mgr base;
    unsigned char *buffer;
    size_t capacity;
} HIJDestination;

static void hij_dest_init(j_compress_ptr cinfo) {
    HIJDestination *dest = (HIJDestination *)cinfo->dest;
    dest->base.next_output_byte = dest->buffer;
    dest->base.free_in_buffer = dest->capacity;
}

static boolean hij_dest_grow(j_compress_ptr cinfo) {
    HIJDestination *dest = (HIJDestination *)cinfo->dest;
    size_t grown = dest->capacity * 2;
    unsigned char *next = realloc(dest->buffer, grown);
    if (next == NULL) ERREXIT1(cinfo, JERR_OUT_OF_MEMORY, 10);
    dest->buffer = next;
    dest->base.next_output_byte = next + dest->capacity;
    dest->base.free_in_buffer = grown - dest->capacity;
    dest->capacity = grown;
    return TRUE;
}

static void hij_dest_term(j_compress_ptr cinfo) {
    (void)cinfo;
}

static int hij_dest_attach(j_compress_ptr cinfo, HIJDestination *dest, size_t initial) {
    dest->capacity = initial < 65536 ? 65536 : initial;
    dest->buffer = malloc(dest->capacity);
    if (dest->buffer == NULL) return 0;
    dest->base.init_destination = hij_dest_init;
    dest->base.empty_output_buffer = hij_dest_grow;
    dest->base.term_destination = hij_dest_term;
    cinfo->dest = &dest->base;
    return 1;
}

static size_t hij_dest_length(HIJDestination *dest) {
    return dest->capacity - dest->base.free_in_buffer;
}

static void hij_set_density(j_compress_ptr cinfo, double dpiX, double dpiY) {
    if (dpiX <= 0 || dpiY <= 0) return;
    /* JFIF implies YCbCr or grey; an RGB-stored JPEG with JFIF would be decoded as YCbCr by many readers. */
    if (cinfo->jpeg_color_space != JCS_YCbCr && cinfo->jpeg_color_space != JCS_GRAYSCALE) return;
    cinfo->write_JFIF_header = TRUE;
    cinfo->density_unit = 1; /* dots per inch */
    cinfo->X_density = (UINT16)(dpiX > 65535 ? 65535 : dpiX + 0.5);
    cinfo->Y_density = (UINT16)(dpiY > 65535 ? 65535 : dpiY + 0.5);
}

/* ICC.1 Annex B: "ICC_PROFILE\0", sequence number, chunk count, then up to 65519 bytes per APP2. */
static void hij_write_icc(j_compress_ptr cinfo, const unsigned char *icc, size_t length) {
    const size_t overhead = 14, maxData = 65533 - overhead;
    size_t chunks = (length + maxData - 1) / maxData, offset = 0;
    if (icc == NULL || length == 0 || chunks > 255) return;
    for (size_t i = 0; i < chunks; i++) {
        size_t size = length - offset < maxData ? length - offset : maxData;
        jpeg_write_m_header(cinfo, JPEG_APP0 + 2, (unsigned int)(size + overhead));
        const char *tag = "ICC_PROFILE";
        for (int k = 0; k < 12; k++) jpeg_write_m_byte(cinfo, k < 11 ? tag[k] : 0);
        jpeg_write_m_byte(cinfo, (int)(i + 1));
        jpeg_write_m_byte(cinfo, (int)chunks);
        for (size_t k = 0; k < size; k++) jpeg_write_m_byte(cinfo, icc[offset + k]);
        offset += size;
    }
}

static void hij_set_sampling(j_compress_ptr cinfo, HIJSubsampling subsampling) {
    if (cinfo->jpeg_color_space != JCS_YCbCr) return;
    int h = subsampling == HIJ_SUB_NONE ? 1 : 2;
    int v = subsampling == HIJ_SUB_HIGH ? 2 : 1;
    cinfo->comp_info[0].h_samp_factor = h;
    cinfo->comp_info[0].v_samp_factor = v;
    for (int c = 1; c < cinfo->num_components; c++) {
        cinfo->comp_info[c].h_samp_factor = 1;
        cinfo->comp_info[c].v_samp_factor = 1;
    }
}

HIJStatus hij_encode_rgba(const unsigned char *rgba, int width, int height, size_t bytesPerRow,
                          const HIJEncodeOptions *options, unsigned char **output, size_t *outputLength) {
    struct jpeg_compress_struct cinfo;
    HIJError err;
    HIJDestination dest = { 0 };
    HIJDestination *volatile dp = &dest; /* read after longjmp; dest itself changes after setjmp */
    unsigned char *volatile row = NULL;
    *output = NULL;
    *outputLength = 0;
    if (rgba == NULL || width <= 0 || height <= 0 || options == NULL) return HIJ_FAILED;

    memset(&cinfo, 0, sizeof cinfo);
    cinfo.err = &err.base;
    hij_install_errors(&err);
    if (setjmp(err.jump)) {
        jpeg_destroy_compress(&cinfo);
        free(row);
        free(dp->buffer);
        return HIJ_FAILED;
    }
    jpeg_create_compress(&cinfo);
    if (!hij_dest_attach(&cinfo, &dest, (size_t)width * (size_t)height / 4)) longjmp(err.jump, 1);

    cinfo.image_width = (JDIMENSION)width;
    cinfo.image_height = (JDIMENSION)height;
    cinfo.input_components = 3;
    cinfo.in_color_space = JCS_RGB;
    jpeg_set_defaults(&cinfo);
    switch (options->colorSpace) {
    case HIJ_RGB: jpeg_set_colorspace(&cinfo, JCS_RGB); break;
    case HIJ_GRAY: jpeg_set_colorspace(&cinfo, JCS_GRAYSCALE); break;
    default: jpeg_set_colorspace(&cinfo, JCS_YCbCr); break;
    }
    jpeg_set_quality(&cinfo, options->quality, TRUE);
    hij_set_sampling(&cinfo, options->subsampling);
    cinfo.smoothing_factor = options->smoothing < 0 ? 0 : (options->smoothing > 100 ? 100 : options->smoothing);
    cinfo.optimize_coding = options->optimizeHuffman ? TRUE : FALSE;
    if (options->progressive) jpeg_simple_progression(&cinfo);
    hij_set_density(&cinfo, options->dpiX, options->dpiY);

    row = malloc((size_t)width * 3);
    if (row == NULL) longjmp(err.jump, 1);
    jpeg_start_compress(&cinfo, TRUE);
    hij_write_icc(&cinfo, options->icc, options->iccLength);
    while (cinfo.next_scanline < cinfo.image_height) {
        const unsigned char *src = rgba + (size_t)cinfo.next_scanline * bytesPerRow;
        for (int x = 0; x < width; x++) memcpy(row + x * 3, src + x * 4, 3);
        JSAMPROW rows[1] = { row };
        jpeg_write_scanlines(&cinfo, rows, 1);
    }
    jpeg_finish_compress(&cinfo);
    jpeg_destroy_compress(&cinfo);
    free(row);
    *output = dest.buffer;
    *outputLength = hij_dest_length(&dest);
    return HIJ_OK;
}

static int hij_marker_is(jpeg_saved_marker_ptr marker, int code, const char *tag, unsigned int tagLength) {
    return marker->marker == code && marker->data_length >= tagLength && memcmp(marker->data, tag, tagLength) == 0;
}

/* Like transupp's jcopy_markers_execute, but the ICC profile always survives (dropping it shifts colours),
   other markers only when metadata is kept, and MPF never (its offsets point past the cropped scan). */
static void hij_copy_markers(j_decompress_ptr src, j_compress_ptr dst, int keepMarkers) {
    for (jpeg_saved_marker_ptr m = src->marker_list; m != NULL; m = m->next) {
        if (dst->write_JFIF_header && hij_marker_is(m, JPEG_APP0, "JFIF", 5)) continue;
        if (dst->write_Adobe_marker && hij_marker_is(m, JPEG_APP0 + 14, "Adobe", 5)) continue;
        if (hij_marker_is(m, JPEG_APP0 + 2, "MPF", 4)) continue;
        if (!keepMarkers && !hij_marker_is(m, JPEG_APP0 + 2, "ICC_PROFILE", 12)) continue;
        jpeg_write_marker(dst, m->marker, m->data, m->data_length);
    }
}

HIJStatus hij_lossless_crop(const unsigned char *jpeg, size_t length, int x, int y, int width, int height,
                            int keepMarkers, int progressive, double dpiX, double dpiY,
                            unsigned char **output, size_t *outputLength) {
    struct jpeg_decompress_struct src;
    struct jpeg_compress_struct dst;
    HIJError err;
    HIJDestination dest = { 0 };
    HIJDestination *volatile dp = &dest;
    volatile HIJStatus failure = HIJ_FAILED;
    jpeg_transform_info info;
    *output = NULL;
    *outputLength = 0;
    if (jpeg == NULL || x < 0 || y < 0 || width <= 0 || height <= 0) return HIJ_FAILED;

    memset(&src, 0, sizeof src);
    memset(&dst, 0, sizeof dst);
    /* One error manager for both objects, so any failure lands in the same cleanup. */
    src.err = &err.base;
    dst.err = &err.base;
    hij_install_errors(&err);
    if (setjmp(err.jump)) {
        jpeg_destroy_compress(&dst);
        jpeg_destroy_decompress(&src);
        free(dp->buffer);
        return failure;
    }
    jpeg_create_decompress(&src);
    jpeg_create_compress(&dst);
    jpeg_mem_src(&src, jpeg, length);
    jcopy_markers_setup(&src, JCOPYOPT_ALL); /* filtered on write by hij_copy_markers */
    jpeg_read_header(&src, TRUE);

    memset(&info, 0, sizeof info);
    info.transform = JXFORM_NONE;
    info.crop = TRUE;
    info.crop_width = (JDIMENSION)width;
    info.crop_width_set = JCROP_FORCE;
    info.crop_height = (JDIMENSION)height;
    info.crop_height_set = JCROP_FORCE;
    info.crop_xoffset = (JDIMENSION)x;
    info.crop_xoffset_set = JCROP_POS;
    info.crop_yoffset = (JDIMENSION)y;
    info.crop_yoffset_set = JCROP_POS;
    if (!jtransform_request_workspace(&src, &info)) longjmp(err.jump, 1);
    if ((int)(info.x_crop_offset * info.iMCU_sample_width) != x ||
        (int)(info.y_crop_offset * info.iMCU_sample_height) != y ||
        (int)info.output_width != width || (int)info.output_height != height) {
        failure = HIJ_UNALIGNED;
        longjmp(err.jump, 1);
    }

    jvirt_barray_ptr *srcCoefficients = jpeg_read_coefficients(&src);
    jpeg_copy_critical_parameters(&src, &dst);
    jvirt_barray_ptr *dstCoefficients = jtransform_adjust_parameters(&src, &dst, srcCoefficients, &info);
    hij_set_density(&dst, dpiX, dpiY);
    dst.optimize_coding = TRUE; /* rebuilt Huffman tables for the smaller region, still lossless */
    if (progressive) jpeg_simple_progression(&dst);
    if (!hij_dest_attach(&dst, &dest, length)) longjmp(err.jump, 1);
    jpeg_write_coefficients(&dst, dstCoefficients);
    hij_copy_markers(&src, &dst, keepMarkers);
    jtransform_execute_transform(&src, &dst, srcCoefficients, &info);
    jpeg_finish_compress(&dst);
    jpeg_destroy_compress(&dst);
    jpeg_destroy_decompress(&src);
    *output = dest.buffer;
    *outputLength = hij_dest_length(&dest);
    return HIJ_OK;
}

void hij_free(unsigned char *buffer) {
    free(buffer);
}

#ifndef CJPEG_SHIM_H
#define CJPEG_SHIM_H

#include <stddef.h>

/* Thin wrapper over the vendored IJG libjpeg 9f, so Swift never sees its macros or setjmp. */

typedef enum { HIJ_YCBCR = 0, HIJ_RGB = 1, HIJ_GRAY = 2 } HIJColorSpace;
typedef enum { HIJ_SUB_NONE = 0, HIJ_SUB_MEDIUM = 1, HIJ_SUB_HIGH = 2 } HIJSubsampling;

typedef struct {
    int quality;              /* 0...100 */
    HIJColorSpace colorSpace; /* stored colour model */
    HIJSubsampling subsampling;
    int smoothing;            /* 0...100 */
    int optimizeHuffman;
    int progressive;
    double dpiX, dpiY;        /* written to the JFIF header; <= 0 leaves it unset */
    const unsigned char *icc; /* optional ICC profile, written as APP2 chunks */
    size_t iccLength;
} HIJEncodeOptions;

typedef enum { HIJ_OK = 0, HIJ_FAILED = 1, HIJ_UNALIGNED = 2 } HIJStatus;

/* Encodes straight (non-premultiplied) RGBA rows; alpha is ignored. */
HIJStatus hij_encode_rgba(const unsigned char *rgba, int width, int height, size_t bytesPerRow,
                          const HIJEncodeOptions *options, unsigned char **output, size_t *outputLength);

/* Crops a JPEG without decoding its pixels. Returns HIJ_UNALIGNED when x/y are not on the source's
   iMCU grid (the caller then re-encodes instead). keepMarkers copies EXIF/IPTC/comments; the ICC profile
   is always kept. dpiX/dpiY <= 0 keep the source's JFIF density. */
HIJStatus hij_lossless_crop(const unsigned char *jpeg, size_t length, int x, int y, int width, int height,
                            int keepMarkers, int progressive, double dpiX, double dpiY,
                            unsigned char **output, size_t *outputLength);

void hij_free(unsigned char *buffer);

#endif

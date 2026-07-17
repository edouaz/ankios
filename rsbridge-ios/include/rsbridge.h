// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

#ifndef ANKI_RSBRIDGE_H
#define ANKI_RSBRIDGE_H

#include <stddef.h>
#include <stdint.h>

typedef struct AnkiBackend AnkiBackend;

typedef struct AnkiByteBuf {
    uint8_t *ptr;
    size_t len;
} AnkiByteBuf;

// Returns NULL if the init message failed to decode.
AnkiBackend *anki_open_backend(const uint8_t *init, size_t len);

// Returns 0 on success (output = protobuf response) or 1 on a backend error
// (output = the encoded BackendError). The caller owns `output` and must
// free it with anki_free_bytes.
int32_t anki_run_command(
    AnkiBackend *backend,
    uint32_t service,
    uint32_t method,
    const uint8_t *input,
    size_t input_len,
    AnkiByteBuf *output);

void anki_free_bytes(AnkiByteBuf buf);

void anki_close_backend(AnkiBackend *backend);

#endif

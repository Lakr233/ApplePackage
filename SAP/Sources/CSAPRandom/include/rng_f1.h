#ifndef SAP_RNG_F1_H
#define SAP_RNG_F1_H
#include <stdint.h>
#include <stddef.h>

/* This is the measured per-word-twist MT variant, not a standard MT stream. */
typedef struct { uint32_t words[624]; uint32_t cursor; } sap_rng_state;
uint32_t sap_rng_word(sap_rng_state *state);

/* Address arguments are explicit 32-bit salts from the target's virtual layout. */
void sap_rng_iv(sap_rng_state *state, uint32_t seed54, uint32_t virtual_output_address,
                uint8_t output[16]);
void sap_rng_f1_material(sap_rng_state *state, uint32_t seed30,
                        uint32_t virtual_first_material_address, uint8_t output[78]);
void sap_f1_from_material(const uint8_t material[78], uint8_t output[256]);
void sap_rng_f1(sap_rng_state *state, uint32_t seed30,
                uint32_t virtual_first_material_address, uint8_t output[256]);
#endif

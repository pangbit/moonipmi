#include <moonbit.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/core_names.h>
#include <string.h>

/* No protocol logic lives here. Return status only, never log key material. */
MOONBIT_FFI_EXPORT int moonipmi_crypto_version(void) {
  return OPENSSL_version_major() == 3;
}

MOONBIT_FFI_EXPORT int moonipmi_random(uint8_t *out, int length) {
  if (length < 1 || length > 1024 || OPENSSL_version_major() != 3) return 0;
  return RAND_bytes(out, length) == 1;
}

MOONBIT_FFI_EXPORT int moonipmi_hmac(const uint8_t *key, int key_length,
    const uint8_t *message, int message_length, uint8_t *out) {
  size_t written = 0;
  if (key_length < 1 || key_length > 64 || message_length < 0 ||
      message_length > 2048 || OPENSSL_version_major() != 3) return 0;
  return EVP_Q_mac(NULL, "HMAC", NULL, "SHA256", NULL,
      key, (size_t) key_length, message, (size_t) message_length,
      out, 32, &written) != NULL && written == 32;
}

MOONBIT_FFI_EXPORT int moonipmi_cbc(int encrypt, const uint8_t *key,
    const uint8_t *iv, const uint8_t *input, int length, uint8_t *out) {
  if (length < 16 || length > 2048 || length % 16 != 0 ||
      OPENSSL_version_major() != 3) return 0;
  EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
  if (ctx == NULL) return 0;
  int written = 0, final = 0;
  int ok = EVP_CipherInit_ex(ctx, EVP_aes_128_cbc(), NULL, key, iv, encrypt) == 1 &&
      EVP_CIPHER_CTX_set_padding(ctx, 0) == 1 &&
      EVP_CipherUpdate(ctx, out, &written, input, length) == 1 &&
      EVP_CipherFinal_ex(ctx, out + written, &final) == 1 &&
      written + final == length;
  EVP_CIPHER_CTX_free(ctx);
  if (!ok) OPENSSL_cleanse(out, (size_t) length);
  return ok;
}

MOONBIT_FFI_EXPORT int moonipmi_equal(const uint8_t *a, const uint8_t *b, int length) {
  if (length < 0 || length > 2048) return 0;
  return CRYPTO_memcmp(a, b, (size_t) length) == 0;
}

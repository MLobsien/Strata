# Apple's metal-cpp C++ headers for the macOS 26 SDK, pinned by the zip's SHA-256.
# The pin comes from metal/setup_mac.py (METAL_CPP_URL / METAL_CPP_SHA256), and setup_mac downloads
# the exact same zip; this fetchurl was additionally verified here: the hash matches that pin.
#
# The zip unpacks as metal-cpp_26/ (Metal/Metal.hpp inside that folder), so the metal.nix derivation
# that uses it must point METAL_CPP_DIR at <this>/metal-cpp_26, not at the store path itself.
{
  fetchurl,
  ...
}:
fetchurl {
  url = "https://developer.apple.com/metal/cpp/files/metal-cpp_26.zip";
  sha256 = "sha256-TfPAeLmq3LUWIS6csDAEy8XOmj6cBo+jFE0CHbWFo6Q=";   # 4df3c078b9aadcb516212e9cb03004cbc5ce9a3e9c068fa3144d021db585a3a4
}

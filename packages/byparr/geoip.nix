{ fetchurl }:

# Merged GeoIP database (GeoLite2 + DB-IP + IP2Location) that invisible-core
# uses to resolve session locale and timezone from the egress IP. Point
# invisible-core at it with STEALTHFOX_GEOIP_MMDB, otherwise it downloads the
# latest build at runtime.
fetchurl {
  name = "geoip-aio-all.mmdb";
  url = "https://github.com/daijro/geoip-all-in-one/releases/download/2026.10.28/geoip-aio-all.mmdb";
  hash = "sha256-KVCbThSG8x8o1NKKmIaEN6Rn8INrY4c/58uRK5CYqmE=";
}

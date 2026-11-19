{ fetchurl }:

# GeoLite2 City database that invisible-core uses to resolve session locale,
# timezone and coordinates from the egress IP. Point
# invisible-core at it with STEALTHFOX_GEOIP_MMDB, otherwise it downloads the
# latest build at runtime.
fetchurl {
  name = "geoip-aio-all.mmdb";
  url = "https://github.com/P3TERX/GeoLite.mmdb/releases/download/2026.11.19/GeoLite2-City.mmdb";
  hash = "sha256-BgqGmdMiluJFNt0j8X5lzhK6SJqc5geSHfCrAeQfozw=";
}

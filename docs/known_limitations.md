# Known System Limitations

This document captures the trade-offs, operational constraints, and architectural boundaries of this system, distinguishing between features that are fine for academic/portfolio purposes and what would be required for a production-grade deployment.

---

## 1. GIS & Geocoding Accuracy

### Local Dev/Portfolio
- **Geocoder**: The system uses **Nominatim (OpenStreetMap)** via `geopy` to resolve free-text addresses.
- **Accuracy**: Nominatim works well for major landmarks, cities, and standard address lines, but often struggles with informal address structures, local slang, or pin-pointing specific door numbers in complex Indian metropolitan neighborhoods (e.g., Chennai).
- **Caching**: Geocoding results are cached locally in memory to respect Nominatim's usage policy.

### Production Requirement
- **Commercial API**: Swap the geocoder provider to **Google Maps Geocoding API** or **MapmyIndia API** for localized, address-matching intelligence that understands landmark-relative descriptions.
- **Persistent Cache**: Store geocoding cache records in a shared PostgreSQL or Redis cache table to prevent redundant API queries across multiple backend web nodes.

---

## 2. Spatial Index Boundaries (Single-Region)

### Local Dev/Portfolio
- **Jurisdictions**: Seeding is limited to 8 adjacent rectangular polygon zones representing mock offices in central Chennai.
- **Failures**: Location queries outside of this bounding box fallback to the closest centroid within 9km or flag the complaint as "uncertain" for manual triaging.

### Production Requirement
- **Scale**: Import complete municipal boundaries (WKT/GeoJSON) for all wards, zones, and administrative districts of the target city or state.
- **Spatial Indexing**: Add database indexes on the geography boundary column:
  ```sql
  CREATE INDEX idx_jurisdictions_boundary ON jurisdictions USING gist (boundary);
  ```

---

## 3. Communication & Gateway Channels

### Local Dev/Portfolio
- **SMS notifications**: The pipeline formats alert messages and records notification rows in the database, but does not send them out to physical devices.
- **Realtime updates**: Relies entirely on Supabase Realtime channel stream connections open on the client device.

### Production Requirement
- **Telephony Gateways**: Integrate SMS microservices using **Twilio**, **Plivo**, or regional SMS gateways to route alerts as physical text messages to field officers.
- **Push Notifications**: Integrate **Firebase Cloud Messaging (FCM)** to support native background push alerts when the citizen app is closed.

---

## 4. Rate Limiting Persistence

### Local Dev/Portfolio
- **Limiter**: Enforces an in-memory token bucket request limiter tracking IP requests.
- **Reset**: Server restarts or deployments clear all limit counters.

### Production Requirement
- **Durable Limiter**: Use **Redis** as a shared rate-limiting store, ensuring that rate limits are enforced consistently across a load-balanced cluster of FastAPI servers.

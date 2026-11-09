const EARTH_RADIUS_METERS: number = 6371000;

export function validateCoordinates(latitude: number, longitude: number): void {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
    latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw new Error('LOCATION_INVALID_COORDINATES');
  }
}

/** Great-circle distance for WGS84 latitude/longitude; result is in meters. */
export function distanceMeters(latitude: number, longitude: number,
  targetLatitude: number, targetLongitude: number): number {
  validateCoordinates(latitude, longitude);
  validateCoordinates(targetLatitude, targetLongitude);
  const radians: number = Math.PI / 180;
  const latitudeDelta: number = (targetLatitude - latitude) * radians;
  const longitudeDelta: number = (targetLongitude - longitude) * radians;
  const haversine: number = Math.pow(Math.sin(latitudeDelta / 2), 2) +
    Math.cos(latitude * radians) * Math.cos(targetLatitude * radians) *
    Math.pow(Math.sin(longitudeDelta / 2), 2);
  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.sqrt(Math.min(1, Math.max(0, haversine))));
}

export function isWithinRadius(latitude: number, longitude: number,
  targetLatitude: number, targetLongitude: number, radiusMeters: number): boolean {
  if (!Number.isFinite(radiusMeters) || radiusMeters <= 0) {
    throw new Error('LOCATION_INVALID_RADIUS');
  }
  // One micrometer only compensates floating-point rounding at the boundary.
  return distanceMeters(latitude, longitude, targetLatitude, targetLongitude) <= radiusMeters + 0.000001;
}

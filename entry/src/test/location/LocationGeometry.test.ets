import { describe, it, expect } from '@ohos/hypium';
import { distanceMeters, isWithinRadius } from '../../main/ets/location/geometry/LocationGeometry';

export default function locationGeometryTest() {
  describe('LocationGeometry', () => {
    it('same_point_is_inside', 0, () => {
      expect(distanceMeters(31, 121, 31, 121)).assertEqual(0);
      expect(isWithinRadius(31, 121, 31, 121, 100)).assertTrue();
    });
    it('one_degree_on_equator_is_about_111_kilometers', 0, () => {
      const distance = distanceMeters(0, 0, 0, 1);
      expect(distance > 111000 && distance < 112000).assertTrue();
      expect(isWithinRadius(0, 0, 0, 1, 1000)).assertFalse();
    });
    it('crosses_date_line_without_taking_long_route', 0, () => {
      const distance = distanceMeters(0, 179.999, 0, -179.999);
      expect(distance > 220 && distance < 225).assertTrue();
    });
    it('includes_exact_boundary', 0, () => {
      const radius = Math.PI * 6371000 / 180;
      expect(isWithinRadius(0, 0, 0, 1, radius)).assertTrue();
    });
    it('rejects_invalid_coordinates_and_radius', 0, () => {
      expect(() => distanceMeters(91, 0, 0, 0)).assertThrowError('LOCATION_INVALID_COORDINATES');
      expect(() => distanceMeters(0, -181, 0, 0)).assertThrowError('LOCATION_INVALID_COORDINATES');
      expect(() => distanceMeters(0, 0, Number.NaN, 0)).assertThrowError('LOCATION_INVALID_COORDINATES');
      expect(() => isWithinRadius(0, 0, 0, 0, 0)).assertThrowError('LOCATION_INVALID_RADIUS');
      expect(() => isWithinRadius(0, 0, 0, 0, Number.POSITIVE_INFINITY)).assertThrowError('LOCATION_INVALID_RADIUS');
    });
  });
}

import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/freeservice/models/free_service_models.dart';
import 'package:enterprise_bike_showroom/features/service/models/service_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for free-service plans and grants.
class FreeServiceRepository {
  FreeServiceRepository(this.supabase);

  final SupabaseService supabase;

  /// All active plans.
  Future<List<FreeServicePlanModel>> plans() async {
    try {
      final dynamic rows = await supabase
          .table('free_service_plans')
          .select()
          .eq('is_active', true)
          .order('name');
      return <FreeServicePlanModel>[
        for (final dynamic row in SafeJson.asList(rows));
          if (row is Map) FreeServicePlanModel.fromJson(SafeJson.asMap(row)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<PaginatedResponse<FreeServiceGrantModel>> listGrants(
      PageQuery query) async {
    try {
      dynamic builder = supabase
          .table('free_service_grants')
          .select('*, vehicle:customer_vehicles(registration_number, chassis_number)');
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'grant_number.ilike.%$term%,vehicle:customer_vehicles(registration_number).ilike.%$term%',
        );
      }
      final String? status = SafeJson.asString(query.filters['status']);
      if (status != null && status.isNotEmpty) {
        builder = builder.eq('status', status);
      }
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);
      builder = builder.range(query.offset, query.end);
      final dynamic result = await (builder).count(CountOption.exact);
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<FreeServiceGrantModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) =>
            FreeServiceGrantModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Grants for one vehicle (shown on the Vehicle 360).
  Future<List<FreeServiceGrantModel>> grantsForVehicle(String vehicleId) async {
    try {
      final dynamic rows = await supabase
          .table('free_service_grants')
          .select()
          .eq('vehicle_id', vehicleId)
          .order('created_at', ascending: false);
      return <FreeServiceGrantModel>[
        for (final dynamic row in SafeJson.asList(rows));
          if (row is Map) FreeServiceGrantModel.fromJson(SafeJson.asMap(row)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Consumes an active grant inside a free service (transactional).
  Future<void> useGrant(String grantId, String serviceId) async {
    try {
      await supabase
          .table('free_service_grants')
          .update(<String, dynamic>{
            'status': 'used',
            'used_service_id': serviceId,
          })
          .eq('id', grantId)
          .eq('status', 'active');
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }
}

/// Marker for downstream failures.
typedef FreeServiceFlowException = AppException;

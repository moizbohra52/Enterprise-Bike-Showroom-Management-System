import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/warranty/models/warranty_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for warranties and claims.
class WarrantyRepository {
  WarrantyRepository(this.supabase);

  final SupabaseService supabase;

  Future<PaginatedResponse<WarrantyModel>> list(PageQuery query) async {
    try {
      var builder = supabase
          .table('warranties')
          .select(
            '*, customer:customers(name, phone), '
            'vehicle:customer_vehicles(registration_number, chassis_number)',
            count: CountOption.exact,
          )
          .range(query.offset, query.end);
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'warranty_number.ilike.%$term%,customer:customers(name).ilike.%$term%,vehicle:customer_vehicles(registration_number).ilike.%$term%',
        );
      }
      final String? status = SafeJson.asString(query.filters['status']);
      if (status != null && status.isNotEmpty) {
        builder = builder.eq('status', status);
      }
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);
      final dynamic result = await builder;
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<WarrantyModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) => WarrantyModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<WarrantyModel?> getById(String id) async {
    try {
      final dynamic row = await supabase
          .table('warranties')
          .select(
            '*, customer:customers(name, phone), '
            'vehicle:customer_vehicles(registration_number, chassis_number)',
          )
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return WarrantyModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Warranties of a vehicle (Vehicle 360).
  Future<List<WarrantyModel>> forVehicle(String vehicleId) async {
    try {
      final dynamic rows = await supabase
          .table('warranties')
          .select()
          .eq('vehicle_id', vehicleId)
          .order('created_at', ascending: false);
      return <WarrantyModel>[
        for (final dynamic row in SafeJson.asList(rows))
          if (row is Map) WarrantyModel.fromJson(SafeJson.asMap(row)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Claims against one warranty.
  Future<List<WarrantyClaimModel>> claims(String warrantyId) async {
    try {
      final dynamic rows = await supabase
          .table('warranty_claims')
          .select()
          .eq('warranty_id', warrantyId)
          .order('created_at', ascending: false);
      return <WarrantyClaimModel>[
        for (final dynamic row in SafeJson.asList(rows))
          if (row is Map) WarrantyClaimModel.fromJson(SafeJson.asMap(row)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Raises a claim (increments claims_count; may open a warranty job).
  Future<WarrantyClaimModel> raiseClaim({
    required String warrantyId,
    required String description,
    num? estimatedCost,
  }) async {
    try {
      final dynamic row = await supabase
          .table('warranty_claims')
          .insert(<String, dynamic>{
            'warranty_id': warrantyId,
            'description': description,
            'estimated_cost': estimatedCost,
          })
          .select()
          .single();
      if (row is! Map) {
        throw AppException('Claim was not created.');
      }
      return WarrantyClaimModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Decides a claim (approve → may link a service job; reject).
  Future<WarrantyClaimModel> decideClaim(
      String claimId, String status, String notes) async {
    try {
      final dynamic row = await supabase
          .table('warranty_claims')
          .update(<String, dynamic>{
            'status': status,
            'decision_notes': notes,
          })
          .eq('id', claimId)
          .select()
          .single();
      if (row is! Map) {
        throw AppException('Claim decision was not saved.');
      }
      return WarrantyClaimModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }
}

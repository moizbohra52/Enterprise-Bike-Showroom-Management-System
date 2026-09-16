import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/insurance/models/insurance_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for insurance policies.
class InsuranceRepository {
  InsuranceRepository(this.supabase);

  final SupabaseService supabase;

  Future<PaginatedResponse<InsurancePolicyModel>> list(PageQuery query) async {
    try {
      dynamic builder = supabase
          .table('insurance_policies')
          .select('*, customer:customers(name, phone), '
            'vehicle:customer_vehicles(registration_number, chassis_number)');
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'policy_number.ilike.%$term%,insurer.ilike.%$term%,customer:customers(name).ilike.%$term%',
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
      return PaginatedResponse<InsurancePolicyModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) =>
            InsurancePolicyModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<InsurancePolicyModel?> getById(String id) async {
    try {
      final dynamic row = await supabase
          .table('insurance_policies')
          .select(
            '*, customer:customers(name, phone), '
            'vehicle:customer_vehicles(registration_number, chassis_number)',
          )
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return InsurancePolicyModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Policies of a vehicle (Vehicle 360).
  Future<List<InsurancePolicyModel>> forVehicle(String vehicleId) async {
    try {
      final dynamic rows = await supabase
          .table('insurance_policies')
          .select()
          .eq('vehicle_id', vehicleId)
          .order('created_at', ascending: false);
      return <InsurancePolicyModel>[
        for (final dynamic row in SafeJson.asList(rows));
          if (row is Map)
            InsurancePolicyModel.fromJson(SafeJson.asMap(row)),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Active customers for the insurance form picker.
  Future<List<Map<String, dynamic>>> activeCustomers() async {
    try {
      final dynamic rows = await supabase
          .table('customers')
          .select('id, name, phone')
          .eq('status', 'active')
          .order('name')
          .limit(100);
      return <Map<String, dynamic>>[
        for (final dynamic row in SafeJson.asList(rows));
          if (row is Map) SafeJson.asMap(row),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Active vehicles of a customer.
  Future<List<Map<String, dynamic>>> customerVehicles(String customerId) async {
    try {
      final dynamic rows = await supabase
          .table('customer_vehicles')
          .select('id, registration_number, chassis_number')
          .eq('customer_id', customerId)
          .eq('status', 'active');
      return <Map<String, dynamic>>[
        for (final dynamic row in SafeJson.asList(rows));
          if (row is Map) SafeJson.asMap(row),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<InsurancePolicyModel> create(Map<String, dynamic> payload) async {
    try {
      final dynamic row = await supabase
          .table('insurance_policies')
          .insert(payload)
          .select()
          .single();
      return InsurancePolicyModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<InsurancePolicyModel> update(
      String id, Map<String, dynamic> patch) async {
    try {
      final dynamic row = await supabase
          .table('insurance_policies')
          .update(patch)
          .eq('id', id)
          .select()
          .single();
      return InsurancePolicyModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }
}

/// Marker for downstream failures.
typedef InsuranceFlowException = AppException;

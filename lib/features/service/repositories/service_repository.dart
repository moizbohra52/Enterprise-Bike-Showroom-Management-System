import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/utils/pagination.dart';
import 'package:enterprise_bike_showroom/core/utils/safe_json.dart';
import 'package:enterprise_bike_showroom/features/service/models/service_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:enterprise_bike_showroom/services/supabase_service.dart';

/// Data access for service records (workshop job cards).
class ServiceRepository {
  ServiceRepository(this.supabase);

  final SupabaseService supabase;

  Future<PaginatedResponse<ServiceRecordModel>> list(PageQuery query) async {
    try {
      var builder = supabase
          .table('service_records')
          .select(
            '*, customer:customers(name, phone), '
            'vehicle:customer_vehicles(registration_number, chassis_number)',
            count: CountOption.exact,
          )
          .range(query.offset, query.end);
      final String? term = query.search;
      if (term != null && term.isNotEmpty) {
        builder = builder.or(
          'service_number.ilike.%$term%,customer:customers(name).ilike.%$term%,vehicle:customer_vehicles(registration_number).ilike.%$term%',
        );
      }
      final String? status = SafeJson.asString(query.filters['status']);
      if (status != null && status.isNotEmpty) {
        builder = builder.eq('status', status);
      }
      final String? jobType = SafeJson.asString(query.filters['job_type']);
      if (jobType != null && jobType.isNotEmpty) {
        builder = builder.eq('job_type', jobType);
      }
      builder = query.orderBy == null
          ? builder.order('created_at', ascending: query.ascending)
          : builder.order(query.orderBy, ascending: query.ascending);
      final dynamic result = await builder;
      // ignore: avoid_dynamic_calls
      final int total = SafeJson.asIntOr(result.count, 0);
      return PaginatedResponse<ServiceRecordModel>.fromSupabase(
        SafeJson.asList(result),
        total: total,
        query: query,
        fromJson: (Map<String, dynamic> json) =>
            ServiceRecordModel.fromJson(json),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  Future<ServiceRecordModel?> getById(String id) async {
    try {
      final dynamic row = await supabase
          .table('service_records')
          .select(
            '*, customer:customers(name, phone), '
            'vehicle:customer_vehicles(registration_number, chassis_number), '
            'service_items(*)',
          )
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return ServiceRecordModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Opens a job card (creates the record + accounting receivable).
  Future<ServiceRecordModel> create({
    required String vehicleId,
    required String customerId,
    required String showroomId,
    required List<ServiceItemModel> items,
    String jobType = 'paid',
    num? odometerIn,
    String? problemDescription,
    DateTime? serviceDate,
  }) async {
    try {
      final dynamic row = await supabase.rpc('open_service_job', <String, dynamic>{
        'p_vehicle_id': vehicleId,
        'p_customer_id': customerId,
        'p_showroom_id': showroomId,
        'p_job_type': jobType,
        'p_odometer_in': odometerIn,
        'p_problem_description': problemDescription,
        'p_service_date':
            (serviceDate ?? DateTime.now()).toIso8601String(),
        'p_items': <Map<String, dynamic>>[
          for (final ServiceItemModel item in items) item.toJson(),
        ],
      });
      if (row is! Map) {
        throw AppException('open_service_job returned no row.');
      }
      return ServiceRecordModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Completes the job (delivery + final billing + accounting).
  Future<ServiceRecordModel> complete({
    required String serviceId,
    required num odometerOut,
    required String workDone,
    num? totalOverride,
    bool collectOnDelivery = true,
    String paymentMode = 'cash',
  }) async {
    try {
      final dynamic row = await supabase.rpc('complete_service', <String, dynamic>{
        'p_service_id': serviceId,
        'p_odometer_out': odometerOut,
        'p_work_done': workDone,
        'p_total_override': totalOverride,
        'p_collect_on_delivery': collectOnDelivery,
        'p_payment_mode': paymentMode,
        'p_completed_at': DateTime.now().toIso8601String(),
      });
      if (row is! Map) {
        throw AppException('complete_service returned no row.');
      }
      return ServiceRecordModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Status update (waiting parts, ready, cancelled).
  Future<ServiceRecordModel> updateStatus(
      String id, String status, {String? notes}) async {
    try {
      final dynamic row = await supabase
          .table('service_records')
          .update(<String, dynamic>{'status': status})
          .eq('id', id)
          .select()
          .single();
      return ServiceRecordModel.fromJson(SafeJson.asMap(row));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Active customers for the service form picker.
  Future<List<Map<String, dynamic>>> activeCustomers() async {
    try {
      final dynamic rows = await supabase
          .table('customers')
          .select('id, name, phone')
          .eq('status', 'active')
          .order('name')
          .limit(100);
      return <Map<String, dynamic>>[
        for (final dynamic row in SafeJson.asList(rows))
          if (row is Map) SafeJson.asMap(row),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// A single customer vehicle (for the pre-selected vehicle flow).
  Future<Map<String, dynamic>?> vehicleById(String id) async {
    try {
      final dynamic row = await supabase
          .table('customer_vehicles')
          .select(
            'id, customer_id, registration_number, chassis_number, current_odometer, product:products(name, model, brand:brands(name))',
          )
          .eq('id', id)
          .maybeSingle();
      if (row is! Map) return null;
      return SafeJson.asMap(row);
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Vehicles of a customer for the service form.
  Future<List<Map<String, dynamic>>> customerVehicles(
      String customerId) async {
    try {
      final dynamic rows = await supabase
          .table('customer_vehicles')
          .select(
            '*, product:products(name, model, brand:brands(name))',
          )
          .eq('customer_id', customerId)
          .eq('status', 'active');
      return <Map<String, dynamic>>[
        for (final dynamic row in SafeJson.asList(rows))
          if (row is Map) SafeJson.asMap(row),
      ];
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }
}

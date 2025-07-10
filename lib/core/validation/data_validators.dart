import 'package:flutter/foundation.dart';
import '../../data/models/bms_data_model.dart';

/// Validation result with detailed information
class ValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? warningMessage;
  final ValidationSeverity severity;
  final DateTime timestamp;

  ValidationResult._({
    required this.isValid,
    this.errorMessage,
    this.warningMessage,
    required this.severity,
    required this.timestamp,
  });

  factory ValidationResult.valid() {
    return ValidationResult._(
      isValid: true,
      severity: ValidationSeverity.info,
      timestamp: DateTime.now(),
    );
  }

  factory ValidationResult.error(String message) {
    return ValidationResult._(
      isValid: false,
      errorMessage: message,
      severity: ValidationSeverity.error,
      timestamp: DateTime.now(),
    );
  }

  factory ValidationResult.warning(String message) {
    return ValidationResult._(
      isValid: true,
      warningMessage: message,
      severity: ValidationSeverity.warning,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'ValidationResult(valid: $isValid, ${errorMessage ?? warningMessage ?? 'OK'})';
  }
}

enum ValidationSeverity { info, warning, error, critical }

/// Base class for all data validators
abstract class DataValidator {
  String get name;
  ValidationSeverity get severity;
  
  ValidationResult validate(JbdBmsData data);
}

/// Validates voltage ranges are within safe limits
class VoltageRangeValidator extends DataValidator {
  @override
  String get name => 'Voltage Range Validator';
  
  @override
  ValidationSeverity get severity => ValidationSeverity.error;

  // Safe operating ranges for LiFePO4 batteries
  static const double minTotalVoltage = 8.0;   // 8V minimum
  static const double maxTotalVoltage = 120.0; // 120V maximum
  static const double minCellVoltage = 2.0;    // 2.0V per cell minimum
  static const double maxCellVoltage = 4.5;    // 4.5V per cell maximum

  @override
  ValidationResult validate(JbdBmsData data) {
    // Validate total voltage
    if (data.totalVoltage < minTotalVoltage) {
      return ValidationResult.error(
        'Total voltage too low: ${data.totalVoltage}V (min: ${minTotalVoltage}V)'
      );
    }
    
    if (data.totalVoltage > maxTotalVoltage) {
      return ValidationResult.error(
        'Total voltage too high: ${data.totalVoltage}V (max: ${maxTotalVoltage}V)'
      );
    }

    // Validate cell voltages
    for (int i = 0; i < data.cellVoltages.length; i++) {
      final cellVoltage = data.cellVoltages[i];
      
      if (cellVoltage < minCellVoltage) {
        return ValidationResult.error(
          'Cell ${i + 1} voltage too low: ${cellVoltage}V (min: ${minCellVoltage}V)'
        );
      }
      
      if (cellVoltage > maxCellVoltage) {
        return ValidationResult.error(
          'Cell ${i + 1} voltage too high: ${cellVoltage}V (max: ${maxCellVoltage}V)'
        );
      }
    }

    // Warning for voltages near limits
    if (data.totalVoltage < minTotalVoltage + 2.0) {
      return ValidationResult.warning(
        'Total voltage approaching minimum: ${data.totalVoltage}V'
      );
    }

    return ValidationResult.valid();
  }
}

/// Validates current readings are reasonable
class CurrentRangeValidator extends DataValidator {
  @override
  String get name => 'Current Range Validator';
  
  @override
  ValidationSeverity get severity => ValidationSeverity.warning;

  static const double maxChargeCurrent = 200.0;    // 200A charge
  static const double maxDischargeCurrent = -300.0; // 300A discharge
  static const double suspiciousCurrentThreshold = 500.0; // Likely sensor error

  @override
  ValidationResult validate(JbdBmsData data) {
    final current = data.current;
    
    // Check for sensor errors
    if (current.abs() > suspiciousCurrentThreshold) {
      return ValidationResult.error(
        'Current reading suspicious: ${current}A (possible sensor error)'
      );
    }

    // Check charge current limits
    if (current > maxChargeCurrent) {
      return ValidationResult.warning(
        'High charge current: ${current}A (max recommended: ${maxChargeCurrent}A)'
      );
    }

    // Check discharge current limits
    if (current < maxDischargeCurrent) {
      return ValidationResult.warning(
        'High discharge current: ${current.abs()}A (max recommended: ${maxDischargeCurrent.abs()}A)'
      );
    }

    return ValidationResult.valid();
  }
}

/// Validates temperature readings
class TemperatureValidator extends DataValidator {
  @override
  String get name => 'Temperature Validator';
  
  @override
  ValidationSeverity get severity => ValidationSeverity.error;

  static const double minOperatingTemp = -20.0;   // -20°C
  static const double maxOperatingTemp = 60.0;    // 60°C
  static const double criticalHighTemp = 55.0;    // 55°C critical
  static const double criticalLowTemp = -15.0;    // -15°C critical

  @override
  ValidationResult validate(JbdBmsData data) {
    for (int i = 0; i < data.temperatures.length; i++) {
      final temp = data.temperatures[i];
      
      // Skip invalid temperature readings
      if (temp.isNaN || temp < -100 || temp > 150) {
        continue;
      }

      // Critical temperature checks
      if (temp > maxOperatingTemp) {
        return ValidationResult.error(
          'Temperature ${i + 1} too high: ${temp.toStringAsFixed(1)}°C (max: $maxOperatingTemp°C)'
        );
      }
      
      if (temp < minOperatingTemp) {
        return ValidationResult.error(
          'Temperature ${i + 1} too low: ${temp.toStringAsFixed(1)}°C (min: $minOperatingTemp°C)'
        );
      }

      // Warning for temperatures approaching limits
      if (temp > criticalHighTemp) {
        return ValidationResult.warning(
          'Temperature ${i + 1} approaching maximum: ${temp.toStringAsFixed(1)}°C'
        );
      }
      
      if (temp < criticalLowTemp) {
        return ValidationResult.warning(
          'Temperature ${i + 1} approaching minimum: ${temp.toStringAsFixed(1)}°C'
        );
      }
    }

    return ValidationResult.valid();
  }
}

/// Validates State of Charge readings
class SocValidator extends DataValidator {
  @override
  String get name => 'SOC Validator';
  
  @override
  ValidationSeverity get severity => ValidationSeverity.warning;

  @override
  ValidationResult validate(JbdBmsData data) {
    final soc = data.chargeLevel;
    
    // SOC should be between 0 and 100
    if (soc < 0 || soc > 100) {
      return ValidationResult.error(
        'Invalid SOC: $soc% (must be 0-100%)'
      );
    }

    // Warning for very low SOC
    if (soc < 10) {
      return ValidationResult.warning(
        'Very low SOC: $soc% - consider charging soon'
      );
    }

    // Warning for very high SOC
    if (soc > 95) {
      return ValidationResult.warning(
        'Very high SOC: $soc% - consider stopping charge'
      );
    }

    return ValidationResult.valid();
  }
}

/// Validates cell voltage balance
class CellBalanceValidator extends DataValidator {
  @override
  String get name => 'Cell Balance Validator';
  
  @override
  ValidationSeverity get severity => ValidationSeverity.warning;

  static const double maxCellImbalance = 0.1; // 100mV max difference
  static const double warningImbalance = 0.05; // 50mV warning

  @override
  ValidationResult validate(JbdBmsData data) {
    if (data.cellVoltages.length < 2) {
      return ValidationResult.valid(); // Can't check balance with < 2 cells
    }

    final maxVoltage = data.cellVoltages.reduce((a, b) => a > b ? a : b);
    final minVoltage = data.cellVoltages.reduce((a, b) => a < b ? a : b);
    final imbalance = maxVoltage - minVoltage;

    if (imbalance > maxCellImbalance) {
      return ValidationResult.error(
        'Severe cell imbalance: ${(imbalance * 1000).toStringAsFixed(0)}mV (max: ${(maxCellImbalance * 1000).toStringAsFixed(0)}mV)'
      );
    }

    if (imbalance > warningImbalance) {
      return ValidationResult.warning(
        'Cell imbalance detected: ${(imbalance * 1000).toStringAsFixed(0)}mV (warning: ${(warningImbalance * 1000).toStringAsFixed(0)}mV)'
      );
    }

    return ValidationResult.valid();
  }
}

/// Validates data consistency over time
class ConsistencyValidator extends DataValidator {
  @override
  String get name => 'Data Consistency Validator';
  
  @override
  ValidationSeverity get severity => ValidationSeverity.warning;

  static JbdBmsData? _lastData;
  static DateTime? _lastValidation;

  @override
  ValidationResult validate(JbdBmsData data) {
    final now = DateTime.now();
    
    if (_lastData != null && _lastValidation != null) {
      final timeDiff = now.difference(_lastValidation!).inSeconds;
      
      // Only check consistency if measurements are close in time
      if (timeDiff < 10) {
        // Check for unrealistic voltage changes
        final voltageDiff = (data.totalVoltage - _lastData!.totalVoltage).abs();
        const maxVoltageChange = 0.5; // 0.5V per second max
        
        if (voltageDiff > maxVoltageChange * timeDiff) {
          return ValidationResult.warning(
            'Suspicious voltage change: ${voltageDiff.toStringAsFixed(2)}V in ${timeDiff}s'
          );
        }

        // Check for unrealistic SOC changes
        final socDiff = (data.chargeLevel - _lastData!.chargeLevel).abs();
        const maxSocChange = 5; // 5% per second max
        
        if (socDiff > maxSocChange * timeDiff) {
          return ValidationResult.warning(
            'Suspicious SOC change: $socDiff% in ${timeDiff}s'
          );
        }
      }
    }
    
    _lastData = data;
    _lastValidation = now;
    
    return ValidationResult.valid();
  }
}

/// Main validation pipeline that runs all validators
class DataValidationPipeline {
  static final List<DataValidator> _validators = [
    VoltageRangeValidator(),
    CurrentRangeValidator(),
    TemperatureValidator(),
    SocValidator(),
    CellBalanceValidator(),
    ConsistencyValidator(),
  ];

  static List<ValidationResult> validateAll(JbdBmsData data) {
    final results = <ValidationResult>[];
    
    for (final validator in _validators) {
      try {
        final result = validator.validate(data);
        results.add(result);
        
        debugPrint('[VALIDATION] ${validator.name}: $result');
        
      } catch (e) {
        debugPrint('[VALIDATION] ❌ Error in ${validator.name}: $e');
        results.add(ValidationResult.error('Validator error: $e'));
      }
    }
    
    return results;
  }

  static ValidationResult validateQuick(JbdBmsData data) {
    // Run only critical validators for performance
    final criticalValidators = _validators.where(
      (v) => v.severity == ValidationSeverity.error || v.severity == ValidationSeverity.critical
    );
    
    for (final validator in criticalValidators) {
      final result = validator.validate(data);
      if (!result.isValid) {
        return result;
      }
    }
    
    return ValidationResult.valid();
  }

  static bool isDataSafe(JbdBmsData data) {
    final result = validateQuick(data);
    return result.isValid;
  }

  static void printValidationSummary(List<ValidationResult> results) {
    final errors = results.where((r) => !r.isValid).length;
    final warnings = results.where((r) => r.isValid && r.warningMessage != null).length;
    
    debugPrint('[VALIDATION] 📊 Summary: ${results.length} checks, $errors errors, $warnings warnings');
    
    for (final result in results) {
      if (!result.isValid || result.warningMessage != null) {
        debugPrint('[VALIDATION] ${result.severity.name.toUpperCase()}: ${result.errorMessage ?? result.warningMessage}');
      }
    }
  }
}
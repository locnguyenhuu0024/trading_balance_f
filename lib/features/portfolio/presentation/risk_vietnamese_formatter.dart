import '../domain/risk/action_plan.dart';
import '../domain/risk/risk_models.dart';

/// Presentation-only copy for the Risk Dashboard.
///
/// The domain and persistence layers intentionally keep their stable English
/// identifiers.  This catalog is the single boundary where those typed values
/// become Vietnamese UI copy.
String riskVi(String key) => _catalog[key] ?? key;

String riskViSeverity(RiskSeverity? severity) {
  if (severity == null) return '-';
  return switch (severity) {
    RiskSeverity.normal => 'BÌNH THƯỜNG',
    RiskSeverity.watch => 'THEO DÕI',
    RiskSeverity.high => 'CAO',
    RiskSeverity.critical => 'NGHIÊM TRỌNG',
  };
}

String riskViQuality(RiskQuality quality) => switch (quality.status) {
  RiskQualityStatus.complete => 'Dữ liệu mới',
  RiskQualityStatus.partial => 'Đánh giá một phần',
  RiskQualityStatus.stale => 'Dữ liệu cũ',
  RiskQualityStatus.error => 'Lỗi kết nối',
  RiskQualityStatus.unsupported => 'Vị thế không được hỗ trợ',
  RiskQualityStatus.empty => 'Chưa chọn vị thế',
  RiskQualityStatus.unavailable => 'Thiếu dữ liệu',
};

String riskViPlanMetric(RiskPlanMetric metric) => switch (metric) {
  RiskPlanMetric.markPrice => 'Giá đánh dấu',
  RiskPlanMetric.buffer => 'Biên thanh lý',
  RiskPlanMetric.effectiveLeverage => 'Đòn bẩy hiệu quả',
  RiskPlanMetric.totalDebt => 'Tổng nợ',
  RiskPlanMetric.dailyHoldingCost => 'Chi phí giữ mỗi ngày',
  RiskPlanMetric.priceVsTrueExit => 'Giá so với True Exit',
  RiskPlanMetric.trueExitPrice => 'Giá True Exit',
};

String riskViPlanComparison(RiskPlanComparison comparison) =>
    switch (comparison) {
      RiskPlanComparison.lessThan => 'Nhỏ hơn',
      RiskPlanComparison.lessThanOrEqual => 'Nhỏ hơn hoặc bằng',
      RiskPlanComparison.greaterThan => 'Lớn hơn',
      RiskPlanComparison.greaterThanOrEqual => 'Lớn hơn hoặc bằng',
      RiskPlanComparison.betweenInclusive => 'Trong khoảng',
    };

String riskViGenerated(String? text) {
  final value = text?.trim() ?? '';
  if (value.isEmpty) return '';
  if (_looksVietnamese(value)) return value;
  final known = _translateGenerated(value);
  return known ?? 'Không thể hiển thị chi tiết rủi ro';
}

String riskViError(String? text, {String? source}) {
  final value = text?.trim() ?? '';
  final translated = _translateGenerated(value);
  if (translated != null) return translated;
  final metadata = <String>[];
  final status = _safeHttpStatus(value);
  if (status != null) metadata.add('HTTP $status');
  final sourceValue = source == null || source.trim().isEmpty
      ? _embeddedSource(value)
      : source.trim();
  if (sourceValue != null && sourceValue.isNotEmpty) {
    metadata.add('nguồn $sourceValue');
  }
  final suffix = metadata.isEmpty ? '' : ' · ${metadata.join(' · ')}';
  return 'Không thể tải dữ liệu rủi ro$suffix';
}

/// Event messages can carry user-authored or source-provided labels. Translate
/// known engine messages while keeping unknown event content intact.
String riskViEvent(String? text) {
  final value = text?.trim() ?? '';
  if (value.isEmpty || _looksVietnamese(value)) return value;
  return _translateGenerated(value) ?? value;
}

/// Translates only labels emitted by the risk engine for Price Map levels.
/// Unknown labels remain byte-for-byte unchanged because they may be user or
/// source authored content.
String riskViPriceMapLabel(String? text) {
  final original = text ?? '';
  final value = original.trim();
  if (value.isEmpty) return original;
  const exact = <String, String>{
    'Current': 'Hiện tại',
    'Entry': 'Điểm vào',
    'Liquidation': 'Thanh lý',
    'True Exit': 'True Exit',
    'Support': 'Hỗ trợ',
    'Resistance': 'Kháng cự',
    'Custom price': 'Giá tùy chỉnh',
    'Known-cost exit estimate': 'Ước tính điểm thoát theo chi phí đã biết',
    'Scenario Position': 'Vị thế kịch bản',
  };
  final known = exact[value];
  if (known != null) return known;
  final buffer = RegExp(r'^Buffer (.+)$').firstMatch(value);
  if (buffer != null) return 'Biên ${buffer.group(1)}';
  final scenario = RegExp(
    r'^([+-]?(?:\d+(?:\.\d+)?|\.\d+)%) scenario$',
  ).firstMatch(value);
  if (scenario != null) return '${scenario.group(1)} kịch bản';
  return original;
}

String riskViEventKind(String value) {
  return const <String, String>{
        'stateChange': 'Thay đổi trạng thái',
        'bufferBoundary': 'Ranh giới biên',
        'leverageBoundary': 'Ranh giới đòn bẩy',
        'marginBoundary': 'Ranh giới tỷ lệ ký quỹ',
        'ruleEntry': 'Kích hoạt quy tắc',
        'zoneEntry': 'Vào vùng giá',
        'factorEntry': 'Yếu tố rủi ro',
        'interestChange': 'Thay đổi lãi',
        'configurationChange': 'Thay đổi cấu hình',
        'reconnect': 'Kết nối lại',
      }[value] ??
      value;
}

String riskViReason(String? text) => riskViGenerated(text);

bool _looksVietnamese(String text) =>
    RegExp(r'[ăâđêôơưĂÂĐÊÔƠƯ]').hasMatch(text);

String? _safeHttpStatus(String text) {
  final match = RegExp(
    r'\bHTTP\s+([1-5]\d{2})\b',
    caseSensitive: false,
  ).firstMatch(text);
  return match?.group(1);
}

String? _embeddedSource(String text) {
  final match = RegExp(
    r'\b(?:source|from|via)\s*[:=]?\s*([A-Za-z0-9][A-Za-z0-9_.-]{0,39})',
    caseSensitive: false,
  ).firstMatch(text);
  return match?.group(1);
}

String _riskEventToken(String value) => const <String, String>{
  'Position': 'Vị thế',
  'Market': 'Thị trường',
  'Recovery': 'Phục hồi',
  'buffer': 'Biên',
  'effective leverage': 'Đòn bẩy hiệu quả',
  'margin ratio': 'Tỷ lệ ký quỹ',
  'normal': 'BÌNH THƯỜNG',
  'watch': 'THEO DÕI',
  'high': 'CAO',
  'critical': 'NGHIÊM TRỌNG',
}[value] ?? value;

String? _translateGenerated(String value) {
  final exact = _generatedCopy[value];
  if (exact != null) return exact;
  final leverage = RegExp(r'^Effective leverage is (.+)$').firstMatch(value);
  if (leverage != null) return 'Đòn bẩy hiệu quả là ${leverage.group(1)}';
  final ratio = RegExp(r'^OKX margin ratio is (.+)$').firstMatch(value);
  if (ratio != null) return 'Tỷ lệ ký quỹ OKX là ${ratio.group(1)}';
  final scenarioBuffer = RegExp(r'^Scenario buffer is (.+)$').firstMatch(value);
  if (scenarioBuffer != null) {
    return 'Biên kịch bản là ${scenarioBuffer.group(1)}';
  }
  final scenarioLeverage = RegExp(
    r'^Scenario leverage is (.+)$',
  ).firstMatch(value);
  if (scenarioLeverage != null) {
    return 'Đòn bẩy kịch bản là ${scenarioLeverage.group(1)}';
  }
  final worsened = RegExp(
    r'^(.+) risk worsened from ([^ ]+) to (.+)$',
  ).firstMatch(value);
  if (worsened != null) {
    return '${_riskEventToken(worsened.group(1)!)} xấu đi từ ${_riskEventToken(worsened.group(2)!)} đến ${_riskEventToken(worsened.group(3)!)}';
  }
  final improvementConfirmed = RegExp(
    r'^(.+) risk improvement confirmed from ([^ ]+) to (.+)$',
  ).firstMatch(value);
  if (improvementConfirmed != null) {
    return '${_riskEventToken(improvementConfirmed.group(1)!)} đã xác nhận cải thiện từ ${_riskEventToken(improvementConfirmed.group(2)!)} đến ${_riskEventToken(improvementConfirmed.group(3)!)}';
  }
  final crossed = RegExp(r'^(.+) crossed (.+)$').firstMatch(value);
  if (crossed != null) {
    return '${_riskEventToken(crossed.group(1)!)} đã vượt ${crossed.group(2)}';
  }
  final riskImprovement = RegExp(
    r'^([^:]+) risk improvement confirmed$',
  ).firstMatch(value);
  if (riskImprovement != null) {
    return 'Đã xác nhận cải thiện rủi ro ${_riskEventToken(riskImprovement.group(1)!)}';
  }
  final structure = RegExp(r'^BTC 4H structure is (.+)$').firstMatch(value);
  if (structure != null) return 'Cấu trúc BTC 4H là ${structure.group(1)}';
  final assetStructure = RegExp(
    r'^([^ ]+) 4H structure is (.+) at (.+)$',
  ).firstMatch(value);
  if (assetStructure != null) {
    return 'Cấu trúc ${assetStructure.group(1)} 4H là ${assetStructure.group(2)} tại ${assetStructure.group(3)}';
  }
  final recovery = RegExp(
    r'^([^ ]+) confirmed support recovery clears its breakdown factor$',
  ).firstMatch(value);
  if (recovery != null) {
    return '${recovery.group(1)} đã xác nhận phục hồi hỗ trợ, loại bỏ yếu tố suy yếu';
  }
  final volatility = RegExp(
    r'^Asset 1H realized volatility is (.+) \((.+)\)$',
  ).firstMatch(value);
  if (volatility != null) {
    return 'Biến động thực tế Asset 1H là ${volatility.group(1)} (${riskViGenerated(volatility.group(2))})';
  }
  final volume = RegExp(
    r'^([^ ]+) latest 4H volume is (.+)x its prior-20 average \((.+)\)$',
  ).firstMatch(value);
  if (volume != null) {
    return 'Khối lượng 4H gần nhất của ${volume.group(1)} bằng ${volume.group(2)}x trung bình 20 kỳ trước (${riskViGenerated(volume.group(3))})';
  }
  final funding = RegExp(
    r'^([^ ]+) funding is (.+) after 8H normalization$',
  ).firstMatch(value);
  if (funding != null) {
    return '${funding.group(1)} có funding ${riskViGenerated(funding.group(2))} sau chuẩn hóa 8H';
  }
  final factorEntry = RegExp(
    r'^New confirmed risk factor: (.+)$',
  ).firstMatch(value);
  if (factorEntry != null) {
    return 'Yếu tố rủi ro mới đã xác nhận: ${factorEntry.group(1)}';
  }
  final liquidationBuffer = RegExp(
    r'^Liquidation buffer is (.+)$',
  ).firstMatch(value);
  if (liquidationBuffer != null) {
    return 'Biên thanh lý là ${liquidationBuffer.group(1)}';
  }
  final bufferVolatility = RegExp(
    r'^Buffer is (.+) daily-volatility units$',
  ).firstMatch(value);
  if (bufferVolatility != null) {
    return 'Biên bằng ${bufferVolatility.group(1)} đơn vị biến động ngày';
  }
  final trueExit = RegExp(
    r'^(Scenario )?True Exit is (.+)% above (mark|price)$',
  ).firstMatch(value);
  if (trueExit != null) {
    final prefix = trueExit.group(1) == null ? '' : 'Kịch bản ';
    final reference = trueExit.group(3) == 'mark' ? 'giá đánh dấu' : 'giá';
    return '${prefix}True Exit cao hơn $reference ${trueExit.group(2)}%';
  }
  final holdingBurden = RegExp(
    r'^(Scenario )?30-day holding burden is (.+)% of equity$',
  ).firstMatch(value);
  if (holdingBurden != null) {
    final prefix = holdingBurden.group(1) == null ? '' : 'Kịch bản ';
    return '${prefix}gánh nặng giữ 30 ngày là ${holdingBurden.group(2)}% vốn chủ sở hữu';
  }
  final reconciliation = RegExp(r'^Debt reconciled as (.+)$').firstMatch(value);
  if (reconciliation != null) {
    return 'Nợ được đối soát theo ${reconciliation.group(1)}';
  }
  final required = RegExp(r'^Required (.+) is unavailable$').firstMatch(value);
  if (required != null) {
    return 'Dữ liệu ${riskViPlanMetricName(required.group(1)!)} bắt buộc chưa khả dụng';
  }
  final rule = RegExp(r'^Action rule entered: (.+)$').firstMatch(value);
  if (rule != null) return 'Đã kích hoạt quy tắc hành động: ${rule.group(1)}';
  final zone = RegExp(r'^Price zone entered: (.+)$').firstMatch(value);
  if (zone != null) return 'Đã vào vùng giá: ${zone.group(1)}';
  return null;
}

const Map<String, String> _catalog = <String, String>{
  'riskHome': 'Trang tổng quan rủi ro',
  'riskOverview': 'Tổng quan rủi ro',
  'showRiskAmounts': 'Hiện số tiền rủi ro',
  'hideRiskAmounts': 'Ẩn số tiền rủi ro',
  'riskSettings': 'Cài đặt rủi ro',
  'yourPlan': 'Kế hoạch của bạn',
  'portfolioDetails': 'Chi tiết danh mục',
  'refresh': 'Làm mới',
  'refreshRiskData': 'Làm mới dữ liệu rủi ro',
  'refreshUnavailable': 'Không thể làm mới',
  'marketInputsReasons': 'Dữ liệu và lý do thị trường',
  'whyThisState': 'Vì sao có trạng thái này',
  'noCompleteReason': 'Chưa có lý do đầy đủ.',
  'exposureSensitivity': 'Mức phơi nhiễm và độ nhạy',
  'exposureUnavailable': 'Không có dữ liệu phơi nhiễm.',
  'recoveryCosts': 'Khả năng phục hồi và chi phí',
  'scenarios': 'Kịch bản',
  'priceMap': 'Bản đồ giá',
  'plan': 'Kế hoạch',
  'history': 'Lịch sử',
  'historyAndChecks': 'Lịch sử và lần kiểm tra',
  'clearHistory': 'Xóa lịch sử',
  'seeAll': 'Xem',
  'overall': 'Tổng thể',
  'debt': 'Nợ',
  'planStatus': 'Kế hoạch',
  'scenarioTenPercent': '-10% kịch bản',
  'position': 'Vị thế',
  'market': 'Thị trường',
  'recovery': 'Phục hồi',
  'buffer': 'Biên',
  'leverage': 'Đòn bẩy',
  'quality': 'Chất lượng',
  'direction': 'Hướng',
  'mode': 'Chế độ',
  'type': 'Loại',
  'freshness': 'Độ mới',
  'failed': 'Thất bại',
  'alert': 'Cảnh báo',
  'quantity': 'Khối lượng',
  'tradeNotional': 'Giá trị giao dịch',
  'grossAssetExposure': 'Phơi nhiễm tài sản gộp',
  'equity': 'Vốn chủ sở hữu',
  'tradeSensitivity': 'Độ nhạy giao dịch / 0.01',
  'equitySensitivity': 'Độ nhạy vốn / 0.01',
  'marginRatio': 'Tỷ lệ ký quỹ',
  'marketRisk': 'Rủi ro thị trường',
  'marketEvidence': 'Bằng chứng thị trường',
  'structure': 'Cấu trúc',
  'volatility': 'Biến động',
  'funding': 'Phí funding',
  'openInterest': 'Lãi mở (OI)',
  'volume': 'Khối lượng',
  'dailyVolatility': 'Biến động ngày',
  'supportResistance': 'Hỗ trợ / kháng cự',
  'fundingInterval': 'Phí funding / khoảng thời gian',
  'oiPriceChange': 'OI / thay đổi giá',
  'partialMarketContext': 'Bối cảnh thị trường một phần',
  'source': 'Nguồn',
  'observed': 'Đã ghi nhận',
  'sourceTime': 'Thời gian nguồn',
  'trueExit': 'True Exit',
  'trueExitPrice': 'Giá True Exit',
  'distanceToTrueExit': 'Khoảng cách đến True Exit',
  'holdingBurden30d': 'Gánh nặng giữ 30 ngày',
  'holdingCostDay': 'Chi phí giữ / ngày',
  'holdingCost7d': 'Chi phí giữ / 7 ngày',
  'holdingCost30d': 'Chi phí giữ / 30 ngày',
  'interestCoverage': 'Mức bao phủ lãi',
  'actualToday': 'Thực tế hôm nay',
  'knownSubtotal': 'Tổng phụ đã biết',
  'projectedTrueExit': 'True Exit dự phóng',
  'knownCostExit': 'Điểm thoát theo chi phí đã biết',
  'trendVelocity': 'Xu hướng và tốc độ',
  'trend': 'Xu hướng',
  'velocity': 'Tốc độ',
  'samples': 'Mẫu',
  'latest': 'Mới nhất',
  'previousCheck': 'Lần kiểm tra trước',
  'noPreviousCheck': 'Chưa có lần kiểm tra trước',
  'dailySummary': 'Tóm tắt hằng ngày',
  'noDailySummary': 'Chưa ghi nhận tóm tắt hằng ngày.',
  'riskEvents': 'Sự kiện rủi ro',
  'noRiskEvents': 'Chưa ghi nhận sự kiện rủi ro.',
  'change': 'Thay đổi',
  'collectingHistory': 'Đang thu thập lịch sử',
  'hidden': 'Đã ẩn',
  'sinceLastCheck': 'Từ lần kiểm tra trước',
  'current': 'Hiện tại',
  'liquidation': 'Thanh lý',
  'liquidationBuffer': 'Biên thanh lý',
  'volatilityMultiple': 'Hệ số biến động',
  'topReasons': 'Lý do',
  'noIsolatedPosition': 'Chưa chọn vị thế isolated',
  'riskDataUnavailable': 'Không có dữ liệu rủi ro',
  'positionUnsupported': 'Vị thế không được hỗ trợ',
  'staleSnapshot': 'Ảnh chụp rủi ro gần nhất đã cũ',
  'partialAssessment': 'Đánh giá rủi ro một phần',
  'waitingRiskData': 'Đang chờ dữ liệu rủi ro',
  'snapshotNeeded':
      'Trang tổng quan rủi ro cần ảnh chụp dữ liệu đầy đủ để đánh giá vị thế.',
  'monitoringActive': 'Đang giám sát',
  'monitoringPaused': 'Đã tạm dừng giám sát',
  'retryingSoon': 'Sẽ thử lại sớm',
  'refreshing': 'Đang làm mới',
  'authenticationBlocked': 'Xác thực bị chặn',
  'partialMonitorUpdate': 'Cập nhật giám sát một phần',
  'monitorReady': 'Giám sát sẵn sàng',
  'monitorUnavailable': 'Giám sát không khả dụng',
  'foreground': 'ứng dụng đang mở',
  'retryTime': 'thời gian thử lại',
  'backgroundUnavailable': 'Chạy nền không khả dụng',
  'selectedPosition': 'Vị thế đã chọn',
  'lastCheck': 'Lần kiểm tra gần nhất',
  'unknown': 'Chưa rõ',
  'atLeast': 'Tối thiểu',
  'lastKnown': 'Đã biết gần nhất',
  'rules': 'Quy tắc',
  'priceZones': 'Vùng giá',
  'createRule': 'Tạo quy tắc',
  'createZone': 'Tạo vùng',
  'editRule': 'Sửa quy tắc',
  'editZone': 'Sửa vùng',
  'edit': 'Sửa',
  'delete': 'Xóa',
  'enable': 'Bật',
  'disable': 'Tắt',
  'cancel': 'Hủy',
  'saveRule': 'Lưu quy tắc',
  'saveZone': 'Lưu vùng',
  'enabled': 'Đã bật',
  'save': 'Lưu',
  'noPlan': 'Chưa có kế hoạch',
  'active': 'đang hoạt động',
  'pending': 'đang chờ',
  'inactive': 'không hoạt động',
  'configured': 'đã cấu hình',
  'rulesNotLoaded': 'Chưa tải quy tắc và vùng',
  'userAuthoredRulesOnly': 'Chỉ gồm quy tắc do người dùng tạo',
  'resetDefaults': 'Đặt lại mặc định',
  'saveRiskSettings': 'Lưu cài đặt rủi ro',
  'riskSettingsDescription':
      'Các ngưỡng dùng phân số nội bộ; thay đổi chính sách sẽ tạo sự kiện cấu hình.',
  'bufferBoundaries': 'Ranh giới biên',
  'effectiveLeverage': 'Đòn bẩy hiệu quả',
  'marginRatioFraction': 'Tỷ lệ ký quỹ (phân số)',
  'historyTimingRetention': 'Thời điểm và thời gian lưu lịch sử',
  'customScenarioPrices': 'Giá kịch bản tùy chỉnh',
  'timeZoneLabel': 'Nhãn múi giờ',
  'dailySummaryHour': 'Giờ tóm tắt hằng ngày',
  'dailySummaryMinute': 'Phút tóm tắt hằng ngày',
  'sampleRetentionDays': 'Số ngày lưu mẫu',
  'oiRetentionHours': 'Số giờ lưu OI',
  'eventRetentionDays': 'Số ngày lưu sự kiện',
  'summaryRetentionDays': 'Số ngày lưu tóm tắt',
  'maximumHistorySamples': 'Số mẫu lịch sử tối đa',
  'maximumOiSamples': 'Số mẫu OI tối đa',
  'maximumEvents': 'Số sự kiện tối đa',
  'maximumEpisodes': 'Số tập tối đa',
  'addPricesHint':
      'Thêm giá trong trình sửa Kịch bản; các dòng biến động theo tỷ lệ vẫn được ghim.',
  'addCustomPrice': 'Thêm giá tùy chỉnh',
  'removeCustomPrice': 'Xóa giá tùy chỉnh',
  'add': 'Thêm',
  'stressScenarios': 'Kịch bản biến động',
  'stressDescription':
      'Nợ và bối cảnh thị trường được giữ nguyên. Tỷ lệ ký quỹ tương lai cố ý hiển thị là -.',
  'stressUnavailable':
      'Kịch bản biến động chưa khả dụng vì vị thế chưa có đủ dữ liệu đầu vào.',
  'priceUsdt': 'Giá (USDT)',
  'hiddenChange': 'Thay đổi đã ẩn',
  'customLevel': 'Mức tùy chỉnh',
  'remove': 'Xóa',
  'priceMapTitle': 'Bản đồ giá sinh tồn',
  'priceMapDescription':
      'Các mức bối cảnh đã sắp xếp. Nhãn mô tả quan sát và vùng do người dùng tạo; chúng không phải hành động thực thi.',
  'priceMapUnavailable': 'Bản đồ giá chưa khả dụng.',
  'observedLevel': 'Mức đã ghi nhận',
  'recoveryRisk': 'Rủi ro phục hồi',
  'noPlanDefined': 'Chưa định nghĩa kế hoạch',
  'partialScenario': 'Kịch bản một phần',
  'engineResultAt': 'Kết quả bộ máy tại',
  'lastKnownScenario': 'Kịch bản đã biết gần nhất',
  'customScenarioPriceSaved': 'Đã lưu giá kịch bản tùy chỉnh',
  'customScenarioPriceRemoved': 'Đã xóa giá kịch bản tùy chỉnh',
  'localChangesUnsaved':
      'Thay đổi rủi ro cục bộ chưa được lưu. Việc gửi đến hệ điều hành vẫn tạm dừng cho đến khi bộ nhớ xác nhận.',
  'privacySemantics':
      'Số tiền hiệu suất được ẩn trên trang tổng quan rủi ro. Mở Chi tiết danh mục để hiện chúng trong lượt này.',
  'privacyNote':
      'Trang tổng quan rủi ro giữ số tiền hiệu suất ngoài màn hình đầu tiên và thông báo. Chi tiết danh mục có bước hiện rõ ràng.',
};

const Map<String, String> _generatedCopy = <String, String>{
  'Bullish': 'Tăng',
  'Bearish': 'Giảm',
  'Neutral': 'Trung tính',
  'Normal': 'Bình thường',
  'High': 'Cao',
  'Low': 'Thấp',
  'Breakdown': 'Suy yếu',
  'Recovery': 'Phục hồi',
  'Weak': 'Yếu',
  'Stable': 'Ổn định',
  'Stable/Neutral': 'Ổn định/Trung tính',
  'Elevated down-volume': 'Khối lượng giảm tăng cao',
  'Elevated up-volume': 'Khối lượng tăng tăng cao',
  'Balanced': 'Cân bằng',
  'Negative': 'Âm',
  'Positive': 'Dương',
  'Strong positive': 'Dương mạnh',
  'Mixed/limited change': 'Thay đổi hỗn hợp/hạn chế',
  '- / Collecting history': '- / Đang thu thập lịch sử',
  'Deteriorating': 'Suy giảm',
  'Improving': 'Cải thiện',
  'Position changed': 'Vị thế đã thay đổi',
  'Stale': 'Cũ',
  '- / Insufficient data': '- / Thiếu dữ liệu',
  'Deteriorating fast': 'Suy giảm nhanh',
  'Improving fast': 'Cải thiện nhanh',
  'Price up / OI up — New leverage entering':
      'Giá tăng / OI tăng — Đòn bẩy mới gia nhập',
  'Price up / OI down — Possible covering':
      'Giá tăng / OI giảm — Có thể đóng vị thế',
  'Price down / OI down — Leverage flushed':
      'Giá giảm / OI giảm — Đòn bẩy bị loại bỏ',
  'Price down / OI up — New positioning during decline':
      'Giá giảm / OI tăng — Mở vị thế mới khi giá giảm',
  'Current': 'Hiện tại',
  'Entry': 'Điểm vào',
  'Liquidation': 'Thanh lý',
  'Mark price is unavailable': 'Giá đánh dấu chưa khả dụng',
  'Complete mark and verified True Exit are required':
      'Cần có giá đánh dấu đầy đủ và True Exit đã xác minh',
  'Position has not observed a snapshot':
      'Vị thế chưa ghi nhận ảnh chụp dữ liệu',
  'Monitor has not observed a snapshot':
      'Bộ giám sát chưa ghi nhận ảnh chụp dữ liệu',
  'Credentials changed; monitoring is restarting':
      'Thông tin xác thực đã thay đổi; đang khởi động lại giám sát',
  'Position risk evaluation failed': 'Đánh giá rủi ro vị thế thất bại',
  'Risk source request failed': 'Yêu cầu đến nguồn rủi ro thất bại',
  'Risk monitor capture failed': 'Lần thu thập của bộ giám sát rủi ro thất bại',
  'OKX perpetual context': 'Bối cảnh hợp đồng vĩnh cửu OKX',
  'Credentials were rejected by the risk source':
      'Nguồn rủi ro từ chối thông tin xác thực',
  'Risk source is backing off after a failed request':
      'Nguồn rủi ro đang tạm lùi sau yêu cầu thất bại',
  'Market source is unavailable': 'Nguồn thị trường chưa khả dụng',
  'Risk settings are read-only; reset is required':
      'Cài đặt rủi ro chỉ đọc; cần đặt lại',
  'Verified input unavailable': 'Dữ liệu đầu vào đã xác minh chưa khả dụng',
  'Debt reconciliation inputs are incomplete':
      'Dữ liệu đầu vào đối soát nợ chưa đầy đủ',
  'Implied isolated debt is invalid': 'Nợ isolated suy ra không hợp lệ',
  'Reported liability is unavailable for reconciliation':
      'Khoản nợ được báo cáo chưa khả dụng để đối soát',
  'Debt reconciled as reported liability plus current interest':
      'Nợ được đối soát bằng khoản nợ báo cáo cộng lãi hiện tại',
  'Debt reconciled as reported liability':
      'Nợ được đối soát theo khoản nợ báo cáo',
  'Equity is zero or negative; leverage is not meaningful':
      'Vốn chủ sở hữu bằng không hoặc âm; đòn bẩy không có ý nghĩa',
  'Mark price is at or below the current liquidation estimate':
      'Giá đánh dấu đang bằng hoặc thấp hơn ước tính thanh lý hiện tại',
  'At/beyond current liquidation estimate; hypothetical only':
      'Đang tại/vượt ước tính thanh lý hiện tại; chỉ là giả định',
  'Strong positive funding adds one crowded-market point':
      'Funding dương mạnh thêm một điểm thị trường quá tải',
  'Positive funding with rising OI and neutral/down price adds one crowded-long point':
      'Funding dương cùng OI tăng và giá đi ngang/giảm thêm một điểm long quá tải',
  'Asset 1H volatility has a nonpositive close':
      'Biến động Asset 1H có giá đóng cửa không dương',
  'Asset 1H daily volatility is zero or unavailable':
      'Biến động ngày Asset 1H bằng không hoặc chưa khả dụng',
  'Asset 4H volume mean is zero or unavailable':
      'Trung bình khối lượng Asset 4H bằng không hoặc chưa khả dụng',
  'Asset 4H volume ratio is unavailable':
      'Tỷ lệ khối lượng Asset 4H chưa khả dụng',
  'Funding rate or settlement interval is unavailable':
      'Tỷ lệ funding hoặc khoảng thời gian thanh toán chưa khả dụng',
  'Adverse BTC structure raises the market state by one level':
      'Cấu trúc BTC bất lợi làm trạng thái thị trường tăng một mức',
  'Action plan configuration changed':
      'Cấu hình kế hoạch hành động đã thay đổi',
  'Risk changed since last observation':
      'Rủi ro đã thay đổi từ lần quan sát trước',
  'Verified True Exit increased by at least 0.25%':
      'True Exit đã xác minh tăng ít nhất 0.25%',
  'Position selection was invalidated': 'Lựa chọn vị thế đã mất hiệu lực',
  'Position batch was invalidated': 'Lô vị thế đã mất hiệu lực',
  'No eligible isolated MARGIN position':
      'Không có vị thế isolated MARGIN đủ điều kiện',
  'No eligible long isolated MARGIN position':
      'Không có vị thế long isolated MARGIN đủ điều kiện',
  'Risk enrichment request failed (HTTP 429)':
      'Yêu cầu bổ sung dữ liệu rủi ro thất bại (HTTP 429)',
  'Monitor is disposed': 'Bộ giám sát đã được giải phóng',
  'Command id is required': 'Cần có mã lệnh',
  'Risk monitor command failed': 'Lệnh giám sát rủi ro thất bại',
  'Risk update': 'Cập nhật rủi ro',
  'Debt reconciliation is incomplete': 'Đối soát nợ chưa đầy đủ',
  'Buffer unavailable: mark and liquidation prices must be positive':
      'Biên chưa khả dụng: giá đánh dấu và giá thanh lý phải dương',
  'Effective leverage unavailable: equity is incomplete':
      'Đòn bẩy hiệu quả chưa khả dụng: vốn chủ sở hữu chưa đầy đủ',
  'Effective leverage unavailable: quantity or mark price is incomplete':
      'Đòn bẩy hiệu quả chưa khả dụng: khối lượng hoặc giá đánh dấu chưa đầy đủ',
  'OKX margin ratio unavailable': 'Tỷ lệ ký quỹ OKX chưa khả dụng',
  'Buffer / daily volatility is unavailable':
      'Biên / biến động ngày chưa khả dụng',
  'Market input is not available': 'Dữ liệu thị trường chưa khả dụng',
  'Market input is unavailable': 'Dữ liệu thị trường chưa khả dụng',
  'Market state is unavailable': 'Trạng thái thị trường chưa khả dụng',
  'True Exit is unavailable or partial':
      'True Exit chưa khả dụng hoặc chưa đầy đủ',
  'Recovery distance is unavailable: True Exit is incomplete':
      'Khoảng cách phục hồi chưa khả dụng: True Exit chưa đầy đủ',
  'Holding burden is unavailable: equity or cost rate is incomplete':
      'Gánh nặng giữ chưa khả dụng: vốn chủ sở hữu hoặc tỷ lệ chi phí chưa đầy đủ',
  'Negative funding after a >=5% 24H decline may indicate increasing short positioning':
      'Funding âm sau khi giá giảm >=5% trong 24H có thể cho thấy vị thế short tăng',
  'Current sample is stale or unavailable':
      'Mẫu hiện tại đã cũ hoặc chưa khả dụng',
  'Baseline positional inputs are incomplete':
      'Dữ liệu đầu vào vị thế cơ sở chưa đầy đủ',
  'Comparable history has a gap greater than 30 minutes':
      'Lịch sử so sánh có khoảng trống lớn hơn 30 phút',
  'Velocity elapsed time is unavailable':
      'Thời gian trôi qua của tốc độ chưa khả dụng',
  'Quantity, margin or debt changed by more than 0.1%':
      'Khối lượng, ký quỹ hoặc nợ đã thay đổi hơn 0.1%',
  'No comparable valid sample at or before now-1h':
      'Không có mẫu hợp lệ để so sánh tại hoặc trước thời điểm hiện tại-1 giờ',
  'No comparable valid sample at or before now-6h':
      'Không có mẫu hợp lệ để so sánh tại hoặc trước thời điểm hiện tại-6 giờ',
  'Rule threshold must be finite': 'Ngưỡng quy tắc phải là số hữu hạn',
  'Rule threshold must be finite and positive':
      'Ngưỡng quy tắc phải là số hữu hạn và dương',
  'Rule thresholds must be finite': 'Các ngưỡng quy tắc phải là số hữu hạn',
  'Rule thresholds must be finite and positive':
      'Các ngưỡng quy tắc phải là số hữu hạn và dương',
  'Buffer thresholds must be between 0% and 100%':
      'Ngưỡng biên phải nằm giữa 0% và 100%',
  'Inclusive range requires two finite thresholds':
      'Khoảng bao gồm cần hai ngưỡng hữu hạn',
  'Inclusive range thresholds must be ordered':
      'Các ngưỡng của khoảng bao gồm phải theo thứ tự',
  'Upper threshold is only valid for inclusive ranges':
      'Ngưỡng trên chỉ hợp lệ với khoảng bao gồm',
  'priceVsTrueExit supports only above/below comparisons':
      'priceVsTrueExit chỉ hỗ trợ so sánh trên/dưới',
  'priceVsTrueExit does not accept numeric thresholds':
      'priceVsTrueExit không nhận ngưỡng số',
  'trueExitPrice is legacy; use priceVsTrueExit':
      'trueExitPrice là tên cũ; hãy dùng priceVsTrueExit',
  'Zone prices must be finite, positive and ordered':
      'Giá vùng phải hữu hạn, dương và theo thứ tự',
  'Zone title must contain 1 to 80 characters':
      'Tiêu đề vùng phải có từ 1 đến 80 ký tự',
  'Rule label must contain 1 to 80 characters':
      'Nhãn quy tắc phải có từ 1 đến 80 ký tự',
  'Rule note must contain 1 to 300 characters when provided':
      'Ghi chú quy tắc phải có từ 1 đến 300 ký tự khi được nhập',
  'Zone note must contain 1 to 300 characters when provided':
      'Ghi chú vùng phải có từ 1 đến 300 ký tự khi được nhập',
  'Rule id is required': 'Cần có mã quy tắc',
  'Rule episodeKey is required': 'Cần có episodeKey của quy tắc',
  'Zone id is required': 'Cần có mã vùng',
  'Zone episodeKey is required': 'Cần có episodeKey của vùng',
  'Plan episodeKey is required': 'Cần có episodeKey của kế hoạch',
};

String riskViPlanMetricName(String value) {
  return switch (value) {
    'markPrice' => 'giá đánh dấu',
    'buffer' => 'biên',
    'effectiveLeverage' => 'đòn bẩy hiệu quả',
    'totalDebt' => 'tổng nợ',
    'dailyHoldingCost' => 'chi phí giữ mỗi ngày',
    'priceVsTrueExit' => 'giá so với True Exit',
    'trueExitPrice' => 'giá True Exit',
    _ => 'rủi ro',
  };
}

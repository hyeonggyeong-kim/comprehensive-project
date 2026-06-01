package com.diary.obd_server.controller;

import com.diary.obd_server.model.DrivingRecord;
import com.diary.obd_server.repository.DrivingRecordRepository;
import com.diary.obd_server.service.EcoDrivingService; // 🟢 연비 서비스 추가
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;


import java.util.*;

@RestController
@RequestMapping("/api/driving")
public class DrivingRecordController {

    @Autowired
    private DrivingRecordRepository drivingRepository;

    // 🟢 연비/위험도 계산 서비스 주입
    @Autowired
    private EcoDrivingService ecoDrivingService;

    // application.properties 의 fastapi.url 값을 자동으로 읽어옴
    @Value("${fastapi.url}")
    private String fastApiUrl;

    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();

    // ================================================================
    // 1. 주행 기록 저장 + 자체 연비 알고리즘 + FastAPI AI 연동
    // ================================================================
    @PostMapping("/save")
    public ResponseEntity<?> saveDrivingRecord(@RequestBody DrivingRecord record) {
        try {
            double avgThrottle = 0, avgLoad = 0, avgCoolant = 0,
                    avgIat = 0, avgMaf = 0, speedDiff = 0, rpmDiff = 0,
                    throttleDiff = 0, speedMa = 0, rpmMa = 0, rpmStd = 0,
                    throttleMa = 0, throttleStd = 0, timingAdvance = 0;
            int count = 0;

            // 앱에서 보낸 JSON을 List<Map> 형태로 변환
            List<Map<String, Object>> logs = new ArrayList<>();

            if (record.getDetailedData() != null && !record.getDetailedData().isEmpty()) {
                logs = objectMapper.readValue(
                        record.getDetailedData(),
                        objectMapper.getTypeFactory()
                                .constructCollectionType(List.class, Map.class)
                );
                count = logs.size();

                List<Double> speeds    = new ArrayList<>();
                List<Double> rpms      = new ArrayList<>();
                List<Double> throttles = new ArrayList<>();

                for (Map<String, Object> log : logs) {
                    speeds.add(toDouble(log.get("speed")));
                    rpms.add(toDouble(log.get("rpm")));
                    throttles.add(toDouble(log.get("throttle")));
                    avgLoad    += toDouble(log.get("load"));
                    avgCoolant += toDouble(log.get("coolant"));
                    avgIat     += toDouble(log.get("iat"));
                    avgMaf     += toDouble(log.get("maf"));
                }

                if (count > 0) {
                    avgLoad    /= count;
                    avgCoolant /= count;
                    avgIat     /= count;
                    avgMaf     /= count;
                }

                // 이동 평균 (3구간) & 표준편차 계산
                speedMa    = movingAvg(speeds, 3);
                rpmMa      = movingAvg(rpms, 3);
                throttleMa = movingAvg(throttles, 3);
                rpmStd     = stdDev(rpms);
                throttleStd = stdDev(throttles);

                if (count >= 2) {
                    speedDiff    = speeds.get(count - 1)    - speeds.get(0);
                    rpmDiff      = rpms.get(count - 1)      - rpms.get(0);
                    throttleDiff = throttles.get(count - 1) - throttles.get(0);
                }
            }

            // ── Step 1. FastAPI /predict 호출 ────────────────────────────
            // 🟢
            Map<String, Object> sensorPayload = new LinkedHashMap<>();
            sensorPayload.put("SPEED",               record.getAvgSpeed());
            sensorPayload.put("ENGINE_RPM",          record.getAvgRpm());
            sensorPayload.put("THROTTLE_POS",        avgThrottle);
            sensorPayload.put("ENGINE_LOAD",         avgLoad);
            sensorPayload.put("ENGINE_COOLANT_TEMP", avgCoolant);
            sensorPayload.put("AIR_INTAKE_TEMP",     avgIat);
            sensorPayload.put("TIMING_ADVANCE",      timingAdvance);
            sensorPayload.put("SPEED_DIFF",          speedDiff);
            sensorPayload.put("RPM_DIFF",            rpmDiff);
            sensorPayload.put("THROTTLE_DIFF",       throttleDiff);
            sensorPayload.put("SPEED_MA",            speedMa);
            sensorPayload.put("RPM_MA",              rpmMa);
            sensorPayload.put("RPM_STD",             rpmStd);
            sensorPayload.put("THROTTLE_MA",         throttleMa);
            sensorPayload.put("THROTTLE_STD",        throttleStd);

            Map<String, Object> fastApiBody = Map.of("data", sensorPayload);
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(fastApiBody, headers);

            double fastApiScore = -1.0; // 실패 여부 확인용
            try {
                ResponseEntity<Map> aiResponse = restTemplate.postForEntity(
                        fastApiUrl + "/predict", request, Map.class
                );
                if (aiResponse.getStatusCode() == HttpStatus.OK
                        && "success".equals(aiResponse.getBody().get("status"))) {
                    fastApiScore = toDouble(aiResponse.getBody().get("predicted_score"));
                }
            } catch (Exception aiEx) {
                System.err.println("[FastAPI 호출 실패] " + aiEx.getMessage());
            }

            // ── Step 2. 자체 연비/에코 알고리즘 호출 ────────────────────────
            // 방금 만든 EcoDrivingService 를 통해 점수 계산
            Map<String, Object> ecoResult = ecoDrivingService.analyzeEcoDriving(logs);
            double ecoScore = (Double) ecoResult.get("risk_score");
            String riskLabel = (String) ecoResult.get("risk_label");

            // ── Step 3. 최종 점수 결정 및 DB 저장 ────────────────────────
            // FastAPI 모델이 정상 응답했다면 그 점수를 우선 사용, 아니라면 자체 연비 점수 사용
            double finalScore = (fastApiScore != -1.0) ? fastApiScore : ecoScore;

            record.setRiskScore(finalScore);
            // 💡 주의: DrivingRecord 엔티티에 riskLabel 필드가 추가되어 있어야 합니다.
            record.setRiskLabel(riskLabel);

            drivingRepository.save(record);

            return ResponseEntity.ok(Map.of(
                    "status",       "success",
                    "message",      "주행 기록 저장 완료",
                    "risk_score",   finalScore,
                    "risk_label",   riskLabel // 앱 UI의 색상을 결정하는 핵심 라벨
            ));

        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(500).body(
                    Map.of("status", "error", "message", e.getMessage())
            );
        }
    }

    // ================================================================
    // 2. 주행 이력 조회
    // ================================================================
    @GetMapping("/history")
    public ResponseEntity<?> getDrivingHistory(@RequestParam String email) {
        List<DrivingRecord> history = drivingRepository.findByUserEmailOrderByIdDesc(email);
        return ResponseEntity.ok(history);
    }

    // ================================================================
    // 3. 주행 기록 삭제
    // ================================================================
    @DeleteMapping("/delete/{id}")
    public ResponseEntity<?> deleteRecord(@PathVariable Long id) {
        drivingRepository.deleteById(id);
        return ResponseEntity.ok(Map.of("status", "success", "message", "삭제되었습니다."));
    }

    // ── 유틸 ──────────────────────────────────────────────────────────
    private double toDouble(Object val) {
        if (val == null) return 0.0;
        try { return Double.parseDouble(val.toString()); }
        catch (NumberFormatException e) { return 0.0; }
    }

    private double movingAvg(List<Double> list, int window) {
        if (list.isEmpty()) return 0.0;
        int from = Math.max(0, list.size() - window);
        return list.subList(from, list.size()).stream()
                .mapToDouble(Double::doubleValue).average().orElse(0.0);
    }

    private double stdDev(List<Double> list) {
        if (list.size() < 2) return 0.0;
        double mean = list.stream().mapToDouble(Double::doubleValue).average().orElse(0.0);
        double variance = list.stream()
                .mapToDouble(v -> Math.pow(v - mean, 2)).average().orElse(0.0);
        return Math.sqrt(variance);
    }
}
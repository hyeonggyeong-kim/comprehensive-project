package com.diary.obd_server.controller;

import com.diary.obd_server.model.DrivingRecord;
import com.diary.obd_server.repository.DrivingRecordRepository;
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

    // application.properties 의 fastapi.url 값을 자동으로 읽어옴
    @Value("${fastapi.url}")
    private String fastApiUrl;

    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();

    // ================================================================
    // 1. 주행 기록 저장 + FastAPI AI 위험도 분석 자동 호출
    // ================================================================
    @PostMapping("/save")
    public ResponseEntity<?> saveDrivingRecord(@RequestBody DrivingRecord record) {
        try {
            // ── Step 1. FastAPI에 보낼 평균 센서값 계산 ──────────────────
            // Flutter가 보낸 detailedData (JSON 배열)를 파싱해 평균 계산
            double avgThrottle = 0, avgLoad = 0, avgCoolant = 0,
                    avgIat = 0, avgMaf = 0, speedDiff = 0, rpmDiff = 0,
                    throttleDiff = 0, speedMa = 0, rpmMa = 0, rpmStd = 0,
                    throttleMa = 0, throttleStd = 0, timingAdvance = 0;
            int count = 0;

            if (record.getDetailedData() != null && !record.getDetailedData().isEmpty()) {
                List<Map<String, Object>> logs = objectMapper.readValue(
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

                // 연속 변화량 (마지막값 - 첫값)
                if (count >= 2) {
                    speedDiff    = speeds.get(count - 1)    - speeds.get(0);
                    rpmDiff      = rpms.get(count - 1)      - rpms.get(0);
                    throttleDiff = throttles.get(count - 1) - throttles.get(0);
                }
            }

            // ── Step 2. FastAPI /predict 호출 ────────────────────────────
            // obd_features.pkl 순서:
            // SPEED, ENGINE_RPM, THROTTLE_POS, ENGINE_LOAD, ENGINE_COOLANT_TEMP,
            // AIR_INTAKE_TEMP, TIMING_ADVANCE, SPEED_DIFF, RPM_DIFF, THROTTLE_DIFF,
            // SPEED_MA, RPM_MA, RPM_STD, THROTTLE_MA, THROTTLE_STD
            Map<String, Object> sensorPayload = new LinkedHashMap<>();
            sensorPayload.put("SPEED",               record.getAvgSpeed());
            sensorPayload.put("ENGINE_RPM",          record.getAvgRpm());
            sensorPayload.put("THROTTLE_POS",        avgThrottle);
            sensorPayload.put("ENGINE_LOAD",         avgLoad);
            sensorPayload.put("ENGINE_COOLANT_TEMP", avgCoolant);
            sensorPayload.put("AIR_INTAKE_TEMP",     avgIat);
            sensorPayload.put("TIMING_ADVANCE",      timingAdvance);  // OBD PID 010E (미수집 시 0)
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

            double predictedScore = 0.0;
            try {
                ResponseEntity<Map> aiResponse = restTemplate.postForEntity(
                        fastApiUrl + "/predict", request, Map.class
                );
                if (aiResponse.getStatusCode() == HttpStatus.OK
                        && "success".equals(aiResponse.getBody().get("status"))) {
                    predictedScore = toDouble(aiResponse.getBody().get("predicted_score"));
                }
            } catch (Exception aiEx) {
                // FastAPI 서버가 꺼져 있어도 주행 기록 저장은 정상 진행
                System.err.println("[FastAPI 호출 실패] " + aiEx.getMessage());
            }

            // ── Step 3. AI 점수를 기록에 붙여서 DB 저장 ─────────────────
            record.setRiskScore(predictedScore);
            drivingRepository.save(record);

            return ResponseEntity.ok(Map.of(
                    "status",       "success",
                    "message",      "주행 기록 저장 완료",
                    "risk_score",   predictedScore,
                    "risk_label",   toLabel(predictedScore)
            ));

        } catch (Exception e) {
            return ResponseEntity.status(500).body(
                    Map.of("status", "error", "message", e.getMessage())
            );
        }
    }

    // ================================================================
    // 2. 주행 이력 조회 (riskScore 포함해서 반환)
    // ================================================================
    @GetMapping("/history")
    public ResponseEntity<?> getDrivingHistory(@RequestParam String email) {
        List<DrivingRecord> history =
                drivingRepository.findByUserEmailOrderByIdDesc(email);
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

    private String toLabel(double score) {
        if (score < 33) return "안전";
        if (score < 66) return "보통";
        return "위험";
    }
}
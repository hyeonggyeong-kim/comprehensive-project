package com.diary.obd_server.controller;

import com.diary.obd_server.model.DrivingRecord;
import com.diary.obd_server.repository.DrivingRecordRepository;
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

    @Value("${fastapi.url}")
    private String fastApiUrl;

    private final RestTemplate restTemplate = new RestTemplate();

    // ================================================================
    // 1. 주행 기록 저장 + FastAPI AI 위험도 분석 자동 호출
    // ================================================================
    @PostMapping("/save")
    public ResponseEntity<?> saveDrivingRecord(@RequestBody DrivingRecord record) {
        try {
            // Step 1. Flutter가 보낸 detailedData를 FastAPI로 전송
            Map<String, Object> fastApiBody = new HashMap<>();
            fastApiBody.put("detailedData", record.getDetailedData());

            // ── 디버그: FastAPI로 보내는 데이터 확인 ──
            System.out.println("===== FastAPI 전송 데이터 =====");
            System.out.println("detailedData 앞 200자: " +
                    (record.getDetailedData() != null
                            ? record.getDetailedData().substring(0, Math.min(200, record.getDetailedData().length()))
                            : "NULL"));
            System.out.println("===============================");

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(fastApiBody, headers);

            double predictedScore = 0.0;
            String drivingStyle   = "unknown";

            // Step 2. FastAPI /predict 호출
            try {
                System.out.println("FastAPI 호출 URL: " + fastApiUrl + "/predict");

                ResponseEntity<Map> aiResponse = restTemplate.postForEntity(
                        fastApiUrl + "/predict", request, Map.class
                );

                System.out.println("FastAPI 응답 코드: " + aiResponse.getStatusCode());
                System.out.println("FastAPI 응답 바디: " + aiResponse.getBody());

                if (aiResponse.getStatusCode() == HttpStatus.OK && aiResponse.getBody() != null) {
                    Map<String, Object> body = aiResponse.getBody();

                    // status 확인
                    String status = (String) body.get("status");
                    if ("success".equals(status)) {
                        predictedScore = toDouble(body.get("predicted_score"));
                        drivingStyle   = body.get("driving_style") != null
                                ? body.get("driving_style").toString() : "unknown";
                    } else {
                        System.err.println("FastAPI 오류 메시지: " + body.get("message"));
                    }
                }
            } catch (Exception aiEx) {
                System.err.println("FastAPI 호출 실패: " + aiEx.getMessage());
                aiEx.printStackTrace();
            }

            // Step 3. AI 점수를 기록에 붙여서 DB 저장
            record.setRiskScore(predictedScore);
            drivingRepository.save(record);

            System.out.println("DB 저장 완료 → 점수: " + predictedScore + " / 성향: " + drivingStyle);

            return ResponseEntity.ok(Map.of(
                    "status",        "success",
                    "message",       "주행 기록 저장 완료",
                    "risk_score",    predictedScore,
                    "risk_label",    toLabel(predictedScore),
                    "driving_style", drivingStyle
            ));

        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(
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
        try {
            return Double.parseDouble(val.toString());
        } catch (NumberFormatException e) {
            return 0.0;
        }
    }

    private String toLabel(double score) {
        if (score == 0.0) return "분석 대기";
        if (score < 33)   return "안전";
        if (score < 66)   return "보통";
        return "위험";
    }
}
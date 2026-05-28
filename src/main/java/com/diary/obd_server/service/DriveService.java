package com.diary.obd_server.service;

import com.diary.obd_server.dto.DriveDto;
import com.diary.obd_server.entity.DriveRecord;
import com.diary.obd_server.repository.DriveRecordRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class DriveService {

    private final DriveRecordRepository driveRecordRepository;
    private final RestTemplate restTemplate;

    @Value("${fastapi.url}")
    private String fastapiUrl;

    public DriveDto.PredictResponse predict(DriveDto.PredictRequest request) {
        try {
            // FastAPI 요청 데이터 구성
            Map<String, Object> sensorData = new HashMap<>();
            if (request.getSpeed()       != null) sensorData.put("SPEED",                   request.getSpeed());
            if (request.getEngineRpm()   != null) sensorData.put("ENGINE_RPM",              request.getEngineRpm());
            if (request.getCoolantTemp() != null) sensorData.put("ENGINE_COOLANT_TEMP",     request.getCoolantTemp());
            if (request.getThrottlePos() != null) sensorData.put("THROTTLE_POS",            request.getThrottlePos());
            if (request.getEngineLoad()  != null) sensorData.put("ENGINE_LOAD",             request.getEngineLoad());
            if (request.getSpeedDiff()   != null) sensorData.put("SPEED_DIFF",              request.getSpeedDiff());
            if (request.getIat()         != null) sensorData.put("IAT_SENSOR",              request.getIat());
            if (request.getMapSensor()   != null) sensorData.put("MAP_SENSOR",              request.getMapSensor());
            if (request.getAccelPedal()  != null) sensorData.put("ACCEL_PEDAL",             request.getAccelPedal());

            Map<String, Object> body = new HashMap<>();
            body.put("data", sensorData);

            // FastAPI 호출
            String endpoint = fastapiUrl + "/predict";
            log.info("FastAPI 호출: {}", endpoint);

            @SuppressWarnings("unchecked")
            Map<String, Object> fastapiResponse = restTemplate.postForObject(
                    endpoint, body, Map.class);

            if (fastapiResponse == null || !"success".equals(fastapiResponse.get("status"))) {
                String errMsg = fastapiResponse != null
                        ? (String) fastapiResponse.get("message") : "FastAPI 응답 없음";
                return DriveDto.PredictResponse.builder()
                        .status("error").message(errMsg).build();
            }

            double score = ((Number) fastapiResponse.get("predicted_score")).doubleValue();
            String style = classifyStyle(score);
            log.info("예측 완료 → 점수: {} / 성향: {}", score, style);

            // DB 저장
            DriveRecord record = DriveRecord.builder()
                    .drivingScore(score)
                    .drivingStyle(style)
                    .speed(request.getSpeed())
                    .engineRpm(request.getEngineRpm())
                    .coolantTemp(request.getCoolantTemp())
                    .throttlePos(request.getThrottlePos())
                    .engineLoad(request.getEngineLoad())
                    .speedDiff(request.getSpeedDiff())
                    .build();
            driveRecordRepository.save(record);

            return DriveDto.PredictResponse.builder()
                    .status("success")
                    .drivingScore(score)
                    .drivingStyle(style)
                    .message("운전 점수 산출 완료")
                    .recordedAt(record.getRecordedAt())
                    .build();

        } catch (Exception e) {
            log.error("예측 중 오류: {}", e.getMessage());
            return DriveDto.PredictResponse.builder()
                    .status("error")
                    .message("서버 오류: " + e.getMessage())
                    .build();
        }
    }

    public List<DriveDto.RecordResponse> getAllRecords() {
        return driveRecordRepository.findAllByOrderByRecordedAtDesc()
                .stream()
                .map(r -> DriveDto.RecordResponse.builder()
                        .id(r.getId())
                        .drivingScore(r.getDrivingScore())
                        .drivingStyle(r.getDrivingStyle())
                        .speed(r.getSpeed())
                        .engineRpm(r.getEngineRpm())
                        .recordedAt(r.getRecordedAt())
                        .build())
                .collect(Collectors.toList());
    }

    public List<DriveDto.RecordResponse> getRecentRecords() {
        return driveRecordRepository.findTop10ByOrderByRecordedAtDesc()
                .stream()
                .map(r -> DriveDto.RecordResponse.builder()
                        .id(r.getId())
                        .drivingScore(r.getDrivingScore())
                        .drivingStyle(r.getDrivingStyle())
                        .speed(r.getSpeed())
                        .engineRpm(r.getEngineRpm())
                        .recordedAt(r.getRecordedAt())
                        .build())
                .collect(Collectors.toList());
    }

    private String classifyStyle(double score) {
        if (score >= 81) return "safe";
        if (score >= 41) return "normal";
        return "aggressive";
    }
}
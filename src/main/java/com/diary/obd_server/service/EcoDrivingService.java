package com.diary.obd_server.service;

import org.springframework.stereotype.Service;
import java.util.List;
import java.util.Map;

@Service
public class EcoDrivingService {

    public Map<String, Object> analyzeEcoDriving(List<Map<String, Object>> detailedData) {

        if (detailedData == null || detailedData.isEmpty()) {
            return Map.of("risk_score", 0.0, "risk_label", "데이터 없음");
        }

        double totalScore = 0.0;
        int dataCount = detailedData.size();
        double prevSpeed = 0.0;

        for (int i = 0; i < dataCount; i++) {
            Map<String, Object> row = detailedData.get(i);

            // 1초 단위 기본 점수 100점에서 시작 (감점/가점제)
            double currentSecondScore = 100.0;

            double speed = toDouble(row.get("speed"));
            double rpm = toDouble(row.get("rpm"));

            // 1. 부드러운 출발 및 정지 (급가속/급제동 감점) [cite: 191, 192, 198]
            // 기존 10.0에서 8.0으로 기준을 조금 더 엄격하게 낮춤 (여유 있는 제동/출발 유도)
            double speedDiff = speed - prevSpeed;
            if (i > 0) {
                if (speedDiff >= 8.0) currentSecondScore -= 20.0;
                else if (speedDiff <= -8.0) currentSecondScore -= 20.0;
            }

            // 2. 적정 RPM 유지 감점 [cite: 157, 181]
            // 수칙에 따르면 2000rpm 전후가 적정 변속 시점이며, 2800rpm 이상은 연비가 크게 저하됨
            if (rpm >= 2500) {
                currentSecondScore -= 10.0;
            }

            // 3. 고속 주행 감점
            // 120km/h로 달리면 연료가 35% 증가하므로 100km/h 이상부터 감점 부여
            if (speed >= 100.0) {
                currentSecondScore -= 15.0;
            }

            // 4. 경제 속도 주행 가점
            // 승용차의 최적 경제 속도인 60~80km/h 구간 유지 시 보너스 점수
            if (speed >= 60.0 && speed <= 80.0) {
                currentSecondScore += 5.0;
            }

            // 5. 불필요한 공회전 감점 [cite: 224, 238]
            // 속도가 0인데 시동이 걸려있는 상태(RPM 500 이상)가 지속되면 감점
            if (speed == 0.0 && rpm > 500.0) {
                currentSecondScore -= 2.0;
            }

            // 점수가 0점 밑으로 내려가거나 100점을 넘지 않도록 보정
            currentSecondScore = Math.max(0, Math.min(100, currentSecondScore));

            totalScore += currentSecondScore;
            prevSpeed = speed;
        }

        double averageScore = totalScore / dataCount;

        // 평균 점수를 바탕으로 최종 라벨링 (안전 기준을 조금 더 현실적으로 70점 / 40점으로 상향)
        String label;
        if (averageScore >= 70) {
            label = "안전 (Eco)";
        } else if (averageScore >= 40) {
            label = "보통 (Normal)";
        } else {
            label = "위험 (Aggressive)";
        }

        return Map.of(
                "risk_score", Math.round(averageScore * 10) / 10.0,
                "risk_label", label
        );
    }

    private double toDouble(Object value) {
        if (value == null) return 0.0;
        try {
            return Double.parseDouble(value.toString());
        } catch (NumberFormatException e) {
            return 0.0;
        }
    }
}
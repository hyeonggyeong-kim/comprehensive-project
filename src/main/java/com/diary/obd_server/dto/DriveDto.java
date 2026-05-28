package com.diary.obd_server.dto;

import lombok.*;
import java.time.LocalDateTime;

public class DriveDto {

    @Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
    public static class PredictRequest {
        private Double speed;
        private Double engineRpm;
        private Double coolantTemp;
        private Double throttlePos;
        private Double engineLoad;
        private Double speedDiff;
        private Double iat;
        private Double mapSensor;
        private Double accelPedal;
    }

    @Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
    public static class PredictResponse {
        private String status;
        private Double drivingScore;
        private String drivingStyle;
        private String message;
        private LocalDateTime recordedAt;
    }

    @Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
    public static class RecordResponse {
        private Long id;
        private Double drivingScore;
        private String drivingStyle;
        private Double speed;
        private Double engineRpm;
        private LocalDateTime recordedAt;
    }
}
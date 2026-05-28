package com.diary.obd_server.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "drive_record")
@Getter @Setter
@NoArgsConstructor @AllArgsConstructor
@Builder
public class DriveRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "driving_score")
    private Double drivingScore;

    @Column(name = "driving_style", length = 20)
    private String drivingStyle;

    @Column(name = "speed")
    private Double speed;

    @Column(name = "engine_rpm")
    private Double engineRpm;

    @Column(name = "coolant_temp")
    private Double coolantTemp;

    @Column(name = "throttle_pos")
    private Double throttlePos;

    @Column(name = "engine_load")
    private Double engineLoad;

    @Column(name = "speed_diff")
    private Double speedDiff;

    @Column(name = "recorded_at")
    private LocalDateTime recordedAt;

    @PrePersist
    public void prePersist() {
        this.recordedAt = LocalDateTime.now();
    }
}
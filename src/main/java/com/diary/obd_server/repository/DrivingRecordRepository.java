package com.diary.obd_server.repository;

import com.diary.obd_server.model.DrivingRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface DrivingRecordRepository extends JpaRepository<DrivingRecord, Long> {
    List<DrivingRecord> findByUserEmailOrderByIdDesc(String userEmail);
}
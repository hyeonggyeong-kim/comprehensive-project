package com.diary.obd_server.repository;

import com.diary.obd_server.entity.DriveRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
import java.util.List;

@Repository
public interface DriveRecordRepository extends JpaRepository<DriveRecord, Long> {
    List<DriveRecord> findTop10ByOrderByRecordedAtDesc();
    List<DriveRecord> findAllByOrderByRecordedAtDesc();
}
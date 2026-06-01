package com.diary.obd_server.repository;

import com.diary.obd_server.model.DtcDictionary;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface DtcDictionaryRepository extends JpaRepository<DtcDictionary, String> {
    // 스프링 부트가 알아서 코드로 뜻을 찾는 마법의 기능을 제공합니다!
    // 🟢
}
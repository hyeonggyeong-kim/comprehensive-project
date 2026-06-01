package com.diary.obd_server.controller;

import com.diary.obd_server.model.DtcDictionary;
import com.diary.obd_server.repository.DtcDictionaryRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/diagnostics")
public class DiagnosticController {

    @Autowired
    private DtcDictionaryRepository dtcDictionaryRepository;

    // 🟢 앱에서 "이 코드 뜻이 뭐야?" 하고 물어보는 창구
    // 🟢
    @GetMapping("/code/{dtcCode}")
    public Map<String, String> getDtcMeaning(@PathVariable String dtcCode) {
        // DB에서 코드를 검색합니다.
        Optional<DtcDictionary> result = dtcDictionaryRepository.findById(dtcCode);

        if (result.isPresent()) {
            // DB에 코드가 있으면 그 뜻을 돌려줍니다.
            return Map.of("code", dtcCode, "description", result.get().getDescription());
        } else {
            // DB에 없는 새로운 코드면 알 수 없다고 돌려줍니다.
            return Map.of("code", dtcCode, "description", "알 수 없는 고장 코드입니다.");
        }
    }
}
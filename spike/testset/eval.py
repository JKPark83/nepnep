#!/usr/bin/env python3
"""M0 스파이크 결과 평가 — CER(jiwer) + DER(pyannote.metrics).

사용법:
    python3 eval.py <result.json> <ref.txt> [ref.rttm]

result.json은 스파이크 앱이 내보낸 파일. ref.rttm을 주면 DER도 계산한다.
"""
import json
import re
import sys

import jiwer


def normalize(text: str) -> str:
    # 문장부호·공백 차이를 무시하고 글자만 비교 (한국어 CER)
    return re.sub(r"[\s.,!?~‘’“”\"'()\[\]·…-]", "", text)


def cer(ref: str, hyp: str) -> float:
    r, h = normalize(ref), normalize(hyp)
    return jiwer.cer(" ".join(r), " ".join(h))


def load_rttm(path):
    from pyannote.core import Annotation, Segment

    ann = Annotation()
    with open(path) as f:
        for line in f:
            parts = line.split()
            if not parts or parts[0] != "SPEAKER":
                continue
            start, dur, spk = float(parts[3]), float(parts[4]), parts[7]
            ann[Segment(start, start + dur)] = spk
    return ann


def hyp_annotation(segments):
    from pyannote.core import Annotation, Segment

    ann = Annotation()
    for s in segments:
        ann[Segment(s["start"], s["end"])] = s["speaker"]
    return ann


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    result = json.load(open(sys.argv[1]))
    ref_text = open(sys.argv[2]).read()

    c = cer(ref_text, result["text"])
    print(f"file={result['file']} engine={result['engine']}")
    print(f"CER: {c:.3f}")
    print(f"transcribe: {result['transcribeSec']:.1f}s  diarize: {result['diarizeSec']:.1f}s")

    if len(sys.argv) > 3:
        from pyannote.metrics.diarization import DiarizationErrorRate

        ref = load_rttm(sys.argv[3])
        hyp = hyp_annotation(result["segments"])
        der = DiarizationErrorRate()(ref, hyp)
        print(f"DER: {der:.3f}")


if __name__ == "__main__":
    main()

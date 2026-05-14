package chunk

import (
	"strings"
	"unicode"
)

func Split(text string, size, overlap int) []string {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}
	if size <= 0 {
		size = 800
	}
	if overlap < 0 || overlap >= size {
		overlap = size / 8
	}

	words := splitWords(text)
	if len(words) == 0 {
		return nil
	}

	var chunks []string
	step := size - overlap
	if step <= 0 {
		step = size
	}
	for start := 0; start < len(words); start += step {
		end := start + size
		if end > len(words) {
			end = len(words)
		}
		chunk := strings.Join(words[start:end], " ")
		chunks = append(chunks, chunk)
		if end == len(words) {
			break
		}
	}
	return chunks
}

func splitWords(text string) []string {
	fields := strings.FieldsFunc(text, func(r rune) bool {
		return unicode.IsSpace(r)
	})
	return fields
}

func ApproxTokenCount(s string) int {
	return len(splitWords(s))
}

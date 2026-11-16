package main

import (
	"testing"
	"time"
)

func TestPresenceRatio(t *testing.T) {
	start := time.Unix(0, 0)
	for _, test := range []struct {
		name    string
		count   int64
		elapsed time.Duration
		want    float64
	}{
		{"minimum window", 1, 20 * time.Second, 1},
		{"partial window", 2, 119 * time.Second, 0.667},
		{"round down", 1, 90 * time.Second, 0.333},
		{"above maximum", 10, 30 * time.Second, 1},
		{"no detections", 0, time.Hour, 0},
		{"future session", 0, -time.Minute, 0},
	} {
		t.Run(test.name, func(t *testing.T) {
			if got := ratio(test.count, start, start.Add(test.elapsed)); got != test.want {
				t.Fatalf("ratio=%g, want %g", got, test.want)
			}
		})
	}
}

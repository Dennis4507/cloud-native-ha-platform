// k6 - a load-testing tool that runs many virtual users (VUs) sending real
// HTTP requests, in parallel, for a set duration. Its job here is to
// generate genuine CPU load against Hello World so the HPA (autoscaler)
// scaling from 2 pods up toward 6-8 during the presentation is a real
// reaction to real traffic, not a staged number.
//
// Run it with: k6 run scripts/load-test.js -e TARGET_URL=https://<ingress-ip>/
// (the -k / insecureSkipTLSVerify option below is what lets k6 accept the
// self-signed certificate without erroring - completely reasonable for a
// load test against infrastructure I control, never something to do
// against a certificate you don't already trust the source of).
import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  insecureSkipTLSVerify: true,
  // Ramping up rather than jumping straight to a high number: this makes
  // the scale-up visible in k9s as a gradual climb (2 -> 4 -> 6...) instead
  // of one instant jump, which reads much better live than a single cliff.
  //
  // The exact VU count needed to push CPU past the HPA's 60% target is
  // genuinely something to confirm by watching `kubectl top pods` during a
  // real rehearsal, not something guessable in advance - NGINX serving one
  // static file is cheap, and TLS termination happens at the ingress, not
  // inside these pods, so the actual CPU cost per request here is small.
  // 300 VUs is a starting point to tune from, not a guaranteed number.
  stages: [
    { duration: '30s', target: 50 },
    { duration: '30s', target: 150 },
    { duration: '2m', target: 300 },
    { duration: '1m', target: 300 },
    { duration: '30s', target: 0 },
  ],
};

const TARGET_URL = __ENV.TARGET_URL || 'https://localhost/';

export default function () {
  http.get(TARGET_URL);
  sleep(0.1);
}

import assert from "node:assert/strict";
import { test } from "node:test";
import { presignRaw } from "../src/lib/storage/sigv4.ts";

test("pré-assinatura igual ao exemplo oficial da AWS (GET com query string)", () => {
  const url = presignRaw({ host: "examplebucket.s3.amazonaws.com", path: "/test.txt", region: "us-east-1",
    accessKeyId: "AKIAIOSFODNN7EXAMPLE", secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", method: "GET",
    expiresIn: 86400, now: new Date("2013-05-24T00:00:00Z") });
  assert.match(url, /X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404$/);
});

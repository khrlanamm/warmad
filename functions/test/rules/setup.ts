import {readFileSync} from "node:fs";
import {resolve} from "node:path";

import {
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";

export const WARUNG = "warungA";
export const OTHER_WARUNG = "warungB";

/** Starts a test environment against the Firestore emulator. */
export function createTestEnv(): Promise<RulesTestEnvironment> {
  return initializeTestEnvironment({
    projectId: "demo-warmad",
    firestore: {
      rules: readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8"),
    },
  });
}

export function owner(env: RulesTestEnvironment, wid = WARUNG) {
  return env.authenticatedContext("owner", {wid, role: "owner"}).firestore();
}

export function cashier(env: RulesTestEnvironment, wid = WARUNG) {
  return env.authenticatedContext("cashier", {wid, role: "cashier"}).firestore();
}

/** Signed in, but not a member of any warung. */
export function buyer(env: RulesTestEnvironment) {
  return env.authenticatedContext("buyer").firestore();
}

export function anonymous(env: RulesTestEnvironment) {
  return env.unauthenticatedContext().firestore();
}

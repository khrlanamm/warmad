import {initializeApp} from "firebase-admin/app";
import {setGlobalOptions} from "firebase-functions/v2";

initializeApp();

// Jakarta, same region as the Firestore database.
setGlobalOptions({region: "asia-southeast2", maxInstances: 10});

export {createWarung} from "./warung/createWarung";

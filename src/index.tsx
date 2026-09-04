import "./index.css";
import React from "react";
import ReactDOM from "react-dom/client";
import { App } from "./App";
import { AdminAuthProvider } from "./features/admin/AdminAuthProvider";

const rootEl = document.getElementById("root");
if (rootEl) {
  ReactDOM.createRoot(rootEl).render(
    <AdminAuthProvider>
      <App />
    </AdminAuthProvider>
  );
}

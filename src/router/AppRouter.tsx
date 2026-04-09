import { RouterProvider } from "react-router-dom";
import { Suspense } from "react";
import { Loader } from "../components/ui/Loader/Loader";
import { useAuthProvider } from "../context/AuthContext";
import { router } from "./Router";

export const AppRouter = () => {

  return (
    <Suspense fallback={<Loader fullScreen text="Loading page..." />}>
      <RouterProvider router={router} />
    </Suspense>
  );
};
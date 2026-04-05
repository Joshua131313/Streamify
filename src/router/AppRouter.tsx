import { BrowserRouter, Route, Routes } from "react-router-dom"
import { AppLayout } from "../components/layout/AppLayout"
import { createBrowserRouter, RouterProvider } from "react-router-dom";
import { lazy, Suspense } from "react"
import { Loader } from "../components/ui/Loader/Loader"
import { Auth } from "../pages/Auth/Auth";
import { Login } from "../pages/Auth/Login";
import { Register } from "../pages/Auth/Register";
import { useAuthProvider } from "../context/AuthContext";
import Home from "../pages/Home/Home";

const Movie = lazy(() => import("../pages/Movie/Movie"));
const Show = lazy(() => import("../pages/Show/Show"));
const Search = lazy(() => import("../pages/Search/Search"));
const Browse = lazy(() => import("../pages/Browse/Browse"));
const SavedMedia = lazy(() => import("../pages/SavedMedia/SavedMedia"));
const PersonPage = lazy(() => import("../pages/Person/Person"));
const SportsPage = lazy(() => import("../pages/Sports/SportsPage"));

const router = createBrowserRouter([
  {
    element: <AppLayout />,
    children: [
      { path: "/", element: <Home /> },
      { path: "search", element: <Search /> },
      { path: "discover", element: <Browse /> },
      { path: "saved-media", element: <SavedMedia /> },
      { path: "person/:id", element: <PersonPage /> },
      { path: "sports", element: <SportsPage /> },
      { path: "login", element: <Login /> },
      { path: "register", element: <Register /> },
    ],
  },
  {
    element: <AppLayout hideNav />,
    children: [
      { path: "movie/:movieId", element: <Movie /> },
      { path: "tv/:showId", element: <Show /> },
    ]
  }
]);

export const AppRouter = () => {
  const { loading } = useAuthProvider();
  if (loading) {
    return <Loader fullScreen text="Streamify is getting ready..." />
  }
  return (
    <Suspense fallback={<Loader fullScreen text="Loading page..." />}>
      <RouterProvider router={router} />
    </Suspense>
  );
};

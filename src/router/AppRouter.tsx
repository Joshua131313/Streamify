import { BrowserRouter, Route, Routes } from "react-router-dom"
import { AppLayout } from "../components/layout/AppLayout"
import { createBrowserRouter, RouterProvider } from "react-router-dom";
import { lazy, Suspense } from "react"
import { Loader } from "../components/ui/Loader/Loader"
import { PersonPage } from "../pages/Person/Person";

const Home = lazy(() => import("../pages/Home/Home"));
const Movie = lazy(() => import("../pages/Movie/Movie"));
const Show = lazy(() => import("../pages/Show/Show"));
const Search = lazy(() => import("../pages/Search/Search"));
const Browse = lazy(() => import("../pages/Browse/Browse"));
const SavedMedia = lazy(() => import("../pages/SavedMedia/SavedMedia"));
const Sports = lazy(() => import("../pages/Sports/Sports"));

const router = createBrowserRouter([
  {
    element: <AppLayout />,
    children: [
      { path: "/", element: <Home /> },
      { path: "movie/:movieId", element: <Movie /> },
      { path: "tv/:showId", element: <Show /> },
      { path: "search", element: <Search /> },
      { path: "discover", element: <Browse /> },
      { path: "saved", element: <SavedMedia /> },
      { path: "person/:id", element: <PersonPage /> },
      { path: "sports", element: <Sports /> }
    ],
  },
]);

export const AppRouter = () => {
  return (
    <Suspense fallback={<Loader fullScreen text="Streamify is getting ready..."/>}>
        <RouterProvider router={router} />
    </Suspense>
  );
};

import NProgress from "nprogress";
import { useEffect } from "react";
import { useLocation } from "react-router-dom";
import "nprogress/nprogress.css";

NProgress.configure({
  showSpinner: false,   // removes spinner
  trickleSpeed: 100,    // speed of automatic progress
  minimum: 0.1,         // starting point
  easing: "ease",
  speed: 400,
});

export const RouteProgress = () => {
  const location = useLocation();

  useEffect(() => {
    NProgress.start();

    const timeout = setTimeout(() => {
      NProgress.done();
      NProgress.configure({})
    }, 300); // small delay for smoothness

    return () => clearTimeout(timeout);
  }, [location]);

  return null;
};
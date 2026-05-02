import NProgress from "nprogress";
import { useEffect } from "react";
import { useLocation } from "react-router-dom";
import "nprogress/nprogress.css";

NProgress.configure({
  showSpinner: false,   
  trickleSpeed: 100,   
  minimum: 0.1,     
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
    }, 300); 

    return () => clearTimeout(timeout);
  }, [location]);

  return null;
};
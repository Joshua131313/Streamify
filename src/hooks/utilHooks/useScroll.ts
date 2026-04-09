import { useEffect } from "react";
import { useLocation } from "react-router-dom";

export function useScroll() {
  const { pathname } = useLocation();

  useEffect(() => {
    const bodyEl = document.querySelector(".body");

    if (bodyEl) {
      bodyEl.scrollTop = 0;
    }

    document.documentElement.scrollTop = 0;
    document.body.scrollTop = 0;
    window.scrollTo(0, 0);

    if (!bodyEl) return;

    const handleScroll = () => {
      if (bodyEl.scrollTop > 10) {
        bodyEl.classList.add("scrolled");
      } else {
        bodyEl.classList.remove("scrolled");
      }
    };

    bodyEl.addEventListener("scroll", handleScroll);

    return () => {
      bodyEl.removeEventListener("scroll", handleScroll);
    };
  }, [pathname]);
}
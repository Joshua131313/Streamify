import { useEffect, useRef } from "react";

export function useMouseIdle(delay = 3000) {
  const timeoutRef = useRef<number | null>(null);

  useEffect(() => {
    const handleActivity = () => {
      // user is active → remove idle class
      document.body.classList.remove("idle");

      // reset timer
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }

      timeoutRef.current = window.setTimeout(() => {
        document.body.classList.add("idle");
      }, delay);
    };

    // track activity
    document.addEventListener("mousemove", handleActivity);

    // start the timer immediately
    handleActivity();

    return () => {
      document.removeEventListener("mousemove", handleActivity);
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
      document.body.classList.remove("idle");
    };
  }, [delay]);
}

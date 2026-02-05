import { useEffect } from "react";

export const useInfiniteScroll = (
  ref: React.RefObject<Element | null>,
  onLoadMore: () => void,
  enabled: boolean
) => {
  useEffect(() => {
    if (!ref.current || !enabled) return;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) onLoadMore();
      },
      { rootMargin: "200px" }
    );

    observer.observe(ref.current);
    return () => observer.disconnect();
  }, [ref, onLoadMore, enabled]);
};

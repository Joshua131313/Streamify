import { FaList } from "react-icons/fa";
import type { TMDBShowMedia } from "../../../types/TMDBMediaType";
import { useMediaLayoutContext } from "../../layout/MediaLayout/MediaLayoutContext";
import { Icon } from "../../ui/Icon/Icon";
import { EpisodesContainer } from "../../../pages/Show/EpisodesContainer";
import { useEffect, useRef, useState } from "react";

export const EpisodeSelector = () => {
  const { media } = useMediaLayoutContext();
  const show: TMDBShowMedia = media as TMDBShowMedia;

  const [showSelector, setShowSelector] = useState(false);

  const iconRef = useRef<HTMLDivElement | null>(null);
  const panelRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const handleMouseDown = (event: MouseEvent) => {
      const target = event.target as Node;

      const clickedIcon = iconRef.current?.contains(target);
      const clickedPanel = panelRef.current?.contains(target);

      if (!clickedIcon && !clickedPanel) {
        setShowSelector(false);
      }
    };

    /** handles iframe clicks */
    const handleWindowBlur = () => {
      setShowSelector(false);
    };

    document.addEventListener("mousedown", handleMouseDown);
    window.addEventListener("blur", handleWindowBlur);

    return () => {
      document.removeEventListener("mousedown", handleMouseDown);
      window.removeEventListener("blur", handleWindowBlur);
    };
  }, []);

  return (
    <div className="episode-selector">
      <div ref={iconRef}>
        <Icon
          Icon={FaList}
          onClick={() => setShowSelector((prev) => !prev)}
          className="episode-selector-icon"
        />
      </div>

      {showSelector && (
        <div ref={panelRef} className="inner-episode-selector">
          <EpisodesContainer show={show} />
        </div>
      )}
    </div>
  );
};

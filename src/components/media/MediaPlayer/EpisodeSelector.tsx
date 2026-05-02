import { FaList } from "react-icons/fa";
import type { TMDBShowMedia } from "../../../types/TMDBMediaType";
import { useMediaLayoutContext } from "../../layout/MediaLayout/MediaLayoutContext";
import { Icon } from "../../ui/Icon/Icon";
import {  useRef, useState } from "react";
import { EpisodesProvider } from "../../../pages/Show/EpisodesProvider";
import { EpisodesControls } from "../../../pages/Show/EpisodesControls";
import { EpisodesList } from "../../../pages/Show/EpisodesList";
import { NextEpisodeIcon } from "./NextEpisodeIcon";

export const EpisodeSelector = () => {
  const { media } = useMediaLayoutContext();
  const show: TMDBShowMedia = media as TMDBShowMedia;

  const [showSelector, setShowSelector] = useState(false);

  const iconRef = useRef<HTMLDivElement | null>(null);
  const panelRef = useRef<HTMLDivElement | null>(null);

  return (
    <div className="episode-selector">
      <div ref={iconRef}>
        <Icon
          Icon={FaList}
          onClick={() => setShowSelector((prev) => !prev)}
          className="episode-selector-icon player-control-icon"
        />
      </div>

      <EpisodesProvider show={show}>
        {
          showSelector && (
            <div ref={panelRef} className="inner-episode-selector">
              <EpisodesControls />
              <EpisodesList />
            </div>
          )}
        <NextEpisodeIcon />
      </EpisodesProvider>

    </div>
  );
};

import React from "react";
import { FaAt } from "react-icons/fa";

import "./GameCard.css";
import type { GameProps } from "../../../types/sports/sportsTypes";

import { WatchButton } from "../../ui/Button/WatchButton";
import ExternalGameInfoButton from "../../ui/Button/ExternalGameInfoButton";
import { GameCardTeam } from "./GameCardTeam";
import { useGameCard } from "./useGameCard";

interface Props {
  game: GameProps;
  showSportName?: boolean;
  className?: string;
}

export const RegularGameCard: React.FC<Props> = ({
  game,
  showSportName,
  className = "",
}) => {
  const {
    openContextMenu,
    defaultSportStreamProvider,
    showPlayButtons,
    getGameStatusUI,
    leadingTeam
  } = useGameCard(game);

  const isLive = game.status === "LIVE" || game.status === "HALFTIME";
  const badgeClass = isLive ? "live-badge" : "not-started-badge";

  const badgeLabel = getGameStatusUI("full").badgeLabel;
  const statusDetail = getGameStatusUI("full").statusDetail;

  return (
    <div
      className={`${className} game-card`}
      onContextMenu={openContextMenu}
    >
      <div className="inner-game-card">
        <div className="game-card-badges">
          <div className={badgeClass}>{badgeLabel}</div>
          {statusDetail && <div className="status-tag">{statusDetail}</div>}
        </div>

        {showSportName && (
          <div className="game-card-sport-name">{game.leagueName}</div>
        )}

        <div className="logos">
          <GameCardTeam game={game} leadingTeam={leadingTeam} teamKey="awayTeam" />
          <span className="vs">
            <FaAt />
          </span>
          <GameCardTeam game={game} leadingTeam={leadingTeam}  teamKey="homeTeam" />
        </div>
      </div>

      <div className={`game-card-buttons ${!showPlayButtons ? "single" : ""}`}>
        <ExternalGameInfoButton url={game.gameLink} />
        {showPlayButtons && (
          <WatchButton
            variant="button"
            awayTeamAbbrev={game.awayTeam.abbrev}
            homeTeamAbbrev={game.homeTeam.abbrev}
            streamProvider={defaultSportStreamProvider}
            league={game.leagueName}
          />
        )}
      </div>
    </div>
  );
};

export default RegularGameCard;
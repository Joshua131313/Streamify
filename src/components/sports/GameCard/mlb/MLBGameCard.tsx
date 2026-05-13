import React from "react";
import { FaArrowUp, FaAt } from "react-icons/fa";

import "./MLBGameCard.css";

import type { GameProps } from "../../../../types/sports/sportsTypes";
import { useGameCard } from "../useGameCard";
import { GameCardTeam } from "../GameCardTeam";

interface Props {
  game: GameProps;
  showSportName?: boolean;
  className?: string;
}

export const MLBGameCard: React.FC<Props> = ({
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
      className={`${className} mlb-game-card`}
      onContextMenu={openContextMenu}
    >
      {/* <div className="inner-game-card">
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
      </div> */}
      <div className="top">
        <div className="left">
        <GameCardTeam game={game} leadingTeam={leadingTeam} teamKey="awayTeam" />
        <div className="inning">
            <FaArrowUp />
            <span>8th</span>
        </div>
      </div>
      <div className="field">
            <div className="diamond">
                <div className="first filled"></div>
                <div className="second"></div>
                <div className="third filled"></div>
            </div>
            <div className="outs">
                <div className="out-1 out filled"></div>
                <div className="out-2 out"></div>
            </div>
      </div>
      <div className="right">
        <GameCardTeam game={game} leadingTeam={leadingTeam}  teamKey="homeTeam" />
        <div className="balls-strikes">
            1-2
        </div>
      </div>
      </div>
      <div className="bottom">
        <div className="pitcher">
            <div className="line-indicator">
                <span>Herrin</span>
                <span>P:4</span>
            </div>
        </div>
        <div className="batter">
            <div className="line-indicator">
                <span>7. Caratini</span>
                <span>0-3</span>
            </div>
        </div>
      </div>
    </div>
  );
};

export default MLBGameCard;
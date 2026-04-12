import { FaX } from "react-icons/fa6";
import { useMultiWatch } from "../../context/MultiWatchContext";
import { getSportStream, getStreamURL } from "../../utils/sports/sportsUtils";
import { StreamPlayerPanel } from "../../components/sports/StreamPlayerPanel/StreamPlayerPanel";



export const MultiWatchContent = () => {
    const { multiWatch, removeGameFromMultiWatch } = useMultiWatch();

    return (
        <>
            {multiWatch.map((g) => (
                <div className="multi-game" key={g.id}>
                    <div className="multi-game-header window-controls">
                        <a className="game-title" href={g.gameLink} target="__blank">
                            {g.homeTeam.abbrev} vs {g.awayTeam.abbrev}
                        </a>
                       <div className="window-close" onClick={() => removeGameFromMultiWatch(g)}>
                         <FaX  />
                       </div>
                    </div>
                    <StreamPlayerPanel 
                        awayAbbrev={g.awayTeam.abbrev}
                        homeAbbrev={g.homeTeam.abbrev}
                        leagueName={g.leagueName}
                    />
                </div>
            ))}
        </>
    );
};
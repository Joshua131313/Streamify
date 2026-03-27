import { FaX } from "react-icons/fa6";
import { useMultiWatch } from "../../context/MultiWatchContext";
import { getSportStream, getStreamURL } from "../../utils/sports/sportsUtils";



export const MultiWatchContent = () => {
    const { multiWatch, removeGameFromMultiWatch } = useMultiWatch();

    return (
        <>
            {multiWatch.map((g) => (
                <div className="multi-game" key={g.id}>
                    <div className="multi-game-header">
                        <a className="game-title" href={g.gameLink} target="__blank">
                            {g.homeTeam.abbrev} vs {g.awayTeam.abbrev}
                        </a>
                        <FaX onClick={() => removeGameFromMultiWatch(g)} />
                    </div>
                    <iframe allowFullScreen src={
                        getSportStream(g.leagueName)[0].buildStreamUrl({
                            awayTeamAbbrev: g.awayTeam.abbrev,
                            homeTeamAbbrev: g.homeTeam.abbrev
                    })} />
                </div>
            ))}
        </>
    );
};
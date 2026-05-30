import { useSports } from "../../../context/SportsContext";
import SportLeaguePage from "./SportsLeaguePage";

const WNBA = () => {
    const { wnbaGameCards, favoriteWNBAGameCards, wnbaGamesLoading } = useSports();

    return (
        <SportLeaguePage
            league="WNBA"
            title="WNBA"
            subTitle="Browse live WNBA games"
            games={wnbaGameCards}
            favoriteGames={favoriteWNBAGameCards}
            gamesLoading={wnbaGamesLoading}
        />
    );
};

export default WNBA;
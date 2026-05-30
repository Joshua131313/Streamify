import { useSports } from "../../../context/SportsContext";
import SportLeaguePage from "./SportsLeaguePage";

const NHL = () => {
    const { nhlGameCards, favoriteNHLGameCards, nhlGamesLoading } = useSports();

    return (
        <SportLeaguePage
            league="NHL"
            title="NHL"
            subTitle="Browse live NHL games"
            games={nhlGameCards}
            favoriteGames={favoriteNHLGameCards}
            gamesLoading={nhlGamesLoading}
        />
    );
};

export default NHL;
import { useSports } from "../../../context/SportsContext";
import SportLeaguePage from "./SportsLeaguePage";

const NBA = () => {
    const { nbaGameCards, favoriteNBAGameCards } = useSports();

    return (
        <SportLeaguePage
            league="NBA"
            title="NBA"
            subTitle="Browse live NBA games"
            games={nbaGameCards}
            favoriteGames={favoriteNBAGameCards}
        />
    );
};

export default NBA;
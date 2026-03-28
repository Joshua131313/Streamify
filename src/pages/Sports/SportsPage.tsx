import { SportsProvider } from "../../context/SportsContext";
import Sports from "./Sports";
import { SportsPlayer } from "./SportsPlayer";


const SportsPage = () => {
    return (
        <>
            <SportsPlayer />
            <SportsProvider>

                <Sports />
            </SportsProvider>
        </>
    );
};
export default SportsPage;
import { FaLongArrowAltLeft } from "react-icons/fa";
import { Button } from "./Button";
import { Icon } from "../Icon/Icon";
import { useApp } from "../../../context/AppContext";
import { useNavigate } from "react-router-dom";


interface Props {
    variant?: "icon" | "button";
}

export const BackButton = (props: Props) => {
    const { variant = "icon" } = props;
    const navigate = useNavigate();
    const { lastMainRoute } = useApp();
    const goBack = () => {
        navigate(lastMainRoute)
    }

    return (
        <>
            {variant === "button" ? (
                <Button className="back-button" onClick={goBack}>
                    Go back
                </Button>
            ) : (
                <Icon className="back-icon" Icon={FaLongArrowAltLeft} onClick={goBack} />
            )}
        </>
    )
}
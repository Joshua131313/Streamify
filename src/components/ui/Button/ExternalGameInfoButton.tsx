import React from "react";
import "./Button.css";

interface Props {
    url: string;
}

const ExternalGameInfoButton: React.FC<Props> = ({ url }) => {

    const type =
        url.includes("espn") ? "espn" :
            url.includes("gamecenter") ? "gamecenter" :
                null
    const imgSrc =
        type === "espn" ? "https://a.espncdn.com/redesign/assets/img/logos/logo-espn-82x20@2x.png" :
            type === "gamecenter" ? "https://media.d3.nhle.com/image/private/t_q-best/prd/assets/nhl/logos/nhl_shield_on_dark_kl1omz" :
                ""
    return (
        <a
            href={url}
            target="_blank"
            rel="noopener noreferrer"
            className={`button external-btn ${type}`}
        >
            <img src={imgSrc} alt="" />
        </a>
    );
};

export default ExternalGameInfoButton;
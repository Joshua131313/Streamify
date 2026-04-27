import { Outlet, useLocation, useNavigation } from "react-router-dom"
import { Navbar } from "../Navbar/Navbar"
import { Footer } from "./Footer/Footer"
import { RouteProgress } from "../../router/RouteProgress";
import { Mobilebar } from "../Navbar/Mobilebar";
import { useScroll } from "../../hooks/utilHooks/useScroll";
import { SportsPlayer } from "../../pages/Sports/SportsPlayer";
import { NetworkIndicatorScreen } from "../ui/NetworkIndicatorScreen/NetworkIndicatorScreen";
import { SportsSidebar } from "../sports/SportsSidebar/SportsSidebar";
import { OnboardingModel } from "../Onboarding/OnboardingModel";
import { useEffect, useState } from "react";
import { useAuthProvider } from "../../context/AuthContext";


interface Props {
    hideNav?: boolean;
    hideFooter?: boolean;
}

export const AppLayout = (props: Props) => {
    const { user, userData, loading } = useAuthProvider();
    const { hideNav, hideFooter } = props;
    const location = useLocation();
    const [openOnboardingModel, setOpenOnboardingModel] = useState(false);

    useScroll();

    useEffect(() => {
        if(loading) return;
        if(!user || !userData) return;
        
        console.log("userdata", userData)
        if(!userData.onboardingComplete) {
            setOpenOnboardingModel(true);
        }

    }, [user, userData, loading])

    return (
        <>
      {/* {!loading ?
        user ? (
          userData?.onboardingComplete ? (
            <Navigate to="/" replace />
          ) : (
            <Navigate to="/customization" replace />
          )
        ) : (
          <Navigate to="/login" replace />
        ) : null
      } */}
      {/* 
                  {
                user ? (
                    userData?.onboardingComplete ? (
                        <Navigate to="/" replace />
                    ) : (
                        <Navigate to="/customization" replace />
                    )
                ) : (
                    null
                )
            }
      */}
            <OnboardingModel open={openOnboardingModel} onClose={() => setOpenOnboardingModel(false)}/>
            <RouteProgress />
            <NetworkIndicatorScreen />
            {!hideNav && <Navbar />}
            <Mobilebar />

            <Outlet />
            <SportsPlayer />
            {location.pathname.includes("sports") && <SportsSidebar />}
            {!hideFooter && <Footer />}
        </>
    )
}
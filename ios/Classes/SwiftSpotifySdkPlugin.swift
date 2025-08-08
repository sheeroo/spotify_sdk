import Flutter
import UIKit
import SpotifyiOS

public class SwiftSpotifySdkPlugin: NSObject, FlutterPlugin, SPTSessionManagerDelegate {
    private static var instance = SwiftSpotifySdkPlugin()
    private var registered = false
    private var authResult: FlutterResult?
    private var sessionManager: SPTSessionManager?
    private var configuration: SPTConfiguration?

    public static func register(with registrar: FlutterPluginRegistrar) {
        guard instance.registered == false else {
            return
        }
        let spotifySDKChannel = FlutterMethodChannel(name: "spotify_sdk", binaryMessenger: registrar.messenger())
        registrar.addApplicationDelegate(instance)
        registrar.addMethodCallDelegate(instance, channel: spotifySDKChannel)
        instance.registered = true
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case SpotifySdkConstants.methodAuthorize:
            handleAuthorize(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleAuthorize(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let swiftArguments = call.arguments as? [String: Any] else {
            result(FlutterError(code: "Argument Error", message: "Invalid arguments", details: nil))
            return
        }
        
        // Validate required parameters
        guard let clientID = swiftArguments[SpotifySdkConstants.paramClientId] as? String,
              !clientID.isEmpty else {
            result(FlutterError(code: "Argument Error", message: "Client ID is not set", details: nil))
            return
        }

        guard let url = swiftArguments[SpotifySdkConstants.paramRedirectUrl] as? String,
              !url.isEmpty else {
            result(FlutterError(code: "Argument Error", message: "Redirect URL is not set", details: nil))
            return
        }

        guard let tokenSwapURLString = swiftArguments[SpotifySdkConstants.paramTokenSwapURL] as? String,
              !tokenSwapURLString.isEmpty else {
            result(FlutterError(code: "Argument Error", message: "Token Swap URL is not set", details: nil))
            return
        }

        guard let tokenRefreshURLString = swiftArguments[SpotifySdkConstants.paramTokenRefreshURL] as? String,
              !tokenRefreshURLString.isEmpty else {
            result(FlutterError(code: "Argument Error", message: "Token Refresh URL is not set", details: nil))
            return
        }
        
        do {
            try authorize(
                clientId: clientID,
                redirectURL: url,
                tokenSwapURL: tokenSwapURLString,
                tokenRefreshURL: tokenRefreshURLString,
                scopes: swiftArguments[SpotifySdkConstants.scopes] as? String,
                playURI: swiftArguments["playURI"] as? String,
                campaign: swiftArguments["campaign"] as? String,
                result: result
            )
        } catch {
            result(FlutterError(code: "Authorization Error", message: error.localizedDescription, details: nil))
        }
    }
    


    private func authorize(
        clientId: String, 
        redirectURL: String, 
        tokenSwapURL: String, 
        tokenRefreshURL: String, 
        scopes: String? = nil,
        playURI: String? = nil,
        campaign: String? = nil,
        result: @escaping FlutterResult
    ) throws {
        
        // Store the result callback
        self.authResult = result
        
        // Create redirect URL
        guard let redirectURL = URL(string: redirectURL) else {
            throw NSError(domain: "SpotifyPlugin", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid redirect URL"])
        }
        
        // Create configuration
        let config = SPTConfiguration(clientID: clientId, redirectURL: redirectURL)
        
        if let tokenSwapURL = URL(string: tokenSwapURL) {
            config.tokenSwapURL = tokenSwapURL
        }
        
        if let tokenRefreshURL = URL(string: tokenRefreshURL) {
            config.tokenRefreshURL = tokenRefreshURL
        }
        
        if let playURI = playURI, !playURI.isEmpty {
            config.playURI = playURI
        } else {
            config.playURI = "" // Empty to resume last track
        }
        
        self.configuration = config
        
        // Create session manager
        self.sessionManager = SPTSessionManager(configuration: config, delegate: self)
        
        // Parse scopes (comma-separated without spaces)
        var requestedScopes: SPTScope = []
        if let scopesString = scopes, !scopesString.isEmpty {
            let scopeArray = scopesString.components(separatedBy: ",")
            requestedScopes = parseScopesFromStrings(scopeArray)
        } else {
            // Default scopes if none provided
            requestedScopes = [.userReadPlaybackState, .userModifyPlaybackState, .userReadCurrentlyPlaying]
        }
        
        // Initiate authentication on main thread
        DispatchQueue.main.async { [weak self] in
            self?.sessionManager?.initiateSession(
                with: requestedScopes,
                options: .default,
                campaign: campaign
            )
        }
    }
    
    private func parseScopesFromStrings(_ scopeStrings: [String]) -> SPTScope {
        var scopes: SPTScope = []
        
        for scopeString in scopeStrings {
            switch scopeString {
            case "appRemoteControl":
                scopes.insert(.appRemoteControl)
            case "userReadPlaybackState":
                scopes.insert(.userReadPlaybackState)
            case "userModifyPlaybackState":
                scopes.insert(.userModifyPlaybackState)
            case "userReadCurrentlyPlaying":
                scopes.insert(.userReadCurrentlyPlaying)
            case "streaming":
                scopes.insert(.streaming)
            case "playlistReadPrivate":
                scopes.insert(.playlistReadPrivate)
            case "playlistReadCollaborative":
                scopes.insert(.playlistReadCollaborative)
            case "playlistModifyPrivate":
                scopes.insert(.playlistModifyPrivate)
            case "playlistModifyPublic":
                scopes.insert(.playlistModifyPublic)
            case "userFollowModify":
                scopes.insert(.userFollowModify)
            case "userFollowRead":
                scopes.insert(.userFollowRead)
            case "userLibraryModify":
                scopes.insert(.userLibraryModify)
            case "userLibraryRead":
                scopes.insert(.userLibraryRead)
            case "userReadEmail":
                scopes.insert(.userReadEmail)
            case "userReadPrivate":
                scopes.insert(.userReadPrivate)
            case "userTopRead":
                scopes.insert(.userTopRead)
            default:
                print("Unknown scope: \(scopeString)")
                break
            }
        }
        
        return scopes
    }
    
    // MARK: - Application Delegate Methods
    public func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return sessionManager?.application(app, open: url, options: options) ?? false
    }
    
    // MARK: - SPTSessionManagerDelegate
    public func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        print("Spotify auth success: \(session)")
        
        let sessionData: [String: Any] = [
            "accessToken": session.accessToken,
            "refreshToken": session.refreshToken ?? "",
            "expirationDate": session.expirationDate.timeIntervalSince1970,
            "scope": session.scope.rawValue
        ]
        
        // Ensure we're on the main thread for Flutter communication
        DispatchQueue.main.async { [weak self] in
            self?.authResult?(sessionData)
            self?.authResult = nil
        }
    }
    
    public func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        print("Spotify auth failed: \(error)")
        
        // Ensure we're on the main thread for Flutter communication
        DispatchQueue.main.async { [weak self] in
            self?.authResult?(FlutterError(
                code: "AUTH_FAILED",
                message: error.localizedDescription,
                details: nil
            ))
            self?.authResult = nil
        }
    }
    
    public func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        print("Spotify session renewed: \(session)")
        
        let sessionData: [String: Any] = [
            "accessToken": session.accessToken,
            "refreshToken": session.refreshToken ?? "",
            "expirationDate": session.expirationDate.timeIntervalSince1970,
            "scope": session.scope.rawValue
        ]
        
        // Ensure we're on the main thread for Flutter communication
        DispatchQueue.main.async { [weak self] in
            self?.authResult?(sessionData)
            self?.authResult = nil
        }
    }
}
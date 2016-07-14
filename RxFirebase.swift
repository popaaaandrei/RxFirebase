//
//  Firebase.swift
//  Healthcare2
//
//  Created by Andrei on 23/05/16.
//  Copyright © 2016 Andrei Popa. All rights reserved.
//

import Foundation
import Firebase
import FirebaseStorage
import RxSwift



// ============================================================================
// MARK: FirebaseError
// ============================================================================
public enum FirebaseError: ErrorType, CustomStringConvertible {
    
    case NotAuthenticated
    case AuthDataNotValid
    case PermissionDenied
    case DownloadError
    case Custom(message: String)

    
    public var description: String {
        switch self {
        case NotAuthenticated:
            return "Not authenticated"
        case AuthDataNotValid:
            return "Authentication data is not valid"
        case .PermissionDenied:
            return "permission denied"
        case .DownloadError:
            return "download error"
        case Custom(let message):
            return "\(message)"
        }
    }
}



// ============================================================================
// MARK: Firebase
// ============================================================================
class Firebase {
    
    static let instance = Firebase()
    
    let rx_user = ReplaySubject<FIRUser?>.create(bufferSize: 1)
    let rx_error = PublishSubject<String>()
    
    // private
    private let disposeBag = DisposeBag()
    var database : FIRDatabaseReference?
    var storage : FIRStorageReference?
    
    
    private init() {
        // firebase
        FIRApp.configure()
        
        database = FIRDatabase.database().reference()
        storage = FIRStorage.storage().reference()
    }

    var clientID : String? {
        return FIRApp.defaultApp()?.options.clientID
    }
    var userID : String? {
        return FIRAuth.auth()?.currentUser?.uid
    }
    
    func signOut() {
        do {
            try FIRAuth.auth()?.signOut()
            rx_user.onNext(nil)
        } catch let signOutError as NSError {
            rx_error.onNext(signOutError.localizedDescription)
        }
    }
}



// ============================================================================
// MARK: AUTH
// ============================================================================
extension Firebase {

    func rx_currentUser() -> Observable<FIRUser> {
        
        if let user = FIRAuth.auth()?.currentUser {
            return Observable.just(user)
        }
        else {
            return Observable.error(FirebaseError.NotAuthenticated)
        }
    }
    
    func rx_authStateDidChange() -> Observable<FIRAuth> {
        
        return Observable.create { (observer : AnyObserver<FIRAuth>) -> Disposable in
            
            let listener = FIRAuth.auth()?.addAuthStateDidChangeListener { auth, _ in
                observer.onNext(auth)
            }
            
            return AnonymousDisposable {
                if let listener = listener {
                    FIRAuth.auth()?.removeAuthStateDidChangeListener(listener)
                }
            }
        }
    }
    
    func rx_signInWithEmail(email: String, password: String) -> Observable<FIRUser> {
        
        guard email.characters.count > 0 && password.characters.count > 0 else {
            return Observable.error(FirebaseError.AuthDataNotValid)
        }
        
        return Observable.create { (observer : AnyObserver<FIRUser>) -> Disposable in
            
            FIRAuth.auth()?.signInWithEmail(email, password: password) { user, error in
                    if let error = error {
                        observer.onError(error)
                    }
                    if let user = user {
                        observer.onNext(user)
                        observer.onCompleted()
                    }
            }
            
            return NopDisposable.instance
        }
    }
    
    func rx_signInWithCredential(credential: FIRAuthCredential) -> Observable<FIRUser> {
        
        return Observable.create { (observer : AnyObserver<FIRUser>) -> Disposable in
            
            FIRAuth.auth()?.signInWithCredential(credential, completion: { user, error in
                if let error = error {
                    observer.onError(error)
                }
                if let user = user {
                    observer.onNext(user)
                    observer.onCompleted()
                }
            })
            
            return NopDisposable.instance
        }
    }
    
    func rx_sendPasswordResetWithEmail(email: String) -> Observable<Void> {
        
        return Observable.create { (observer : AnyObserver<Void>) -> Disposable in
            
            FIRAuth.auth()?.sendPasswordResetWithEmail(email) { error in
                if let error = error {
                    observer.onError(FirebaseError.Custom(message: error.localizedDescription))
                } else {
                    observer.onNext()
                    observer.onCompleted()
                }
            }
            
            return NopDisposable.instance
        }
    }
    
    func rx_createUser(email: String, password: String) -> Observable<FIRUser> {
        
        guard email.characters.count > 0 && password.characters.count > 0 else {
            return Observable.error(FirebaseError.AuthDataNotValid)
        }
        
        return Observable.create { (observer : AnyObserver<FIRUser>) -> Disposable in
            
            FIRAuth.auth()?.createUserWithEmail(email, password: password) { user, error in
                    if let error = error {
                        observer.onError(error)
                    }
                    if let user = user {
                        observer.onNext(user)
                        observer.onCompleted()
                    }
            }
            
            return NopDisposable.instance
        }
    }
    
    func rx_publish(object: AnyObject, atPath: String) -> Observable<Void> {
        
        guard let database = Firebase.instance.database else {
            return Observable.error(FirebaseError.PermissionDenied)
        }
        
        return database
            .root
            .child(atPath)
            .rx_setValue(object)
    }
}


// ============================================================================
// MARK: STORAGE
// ============================================================================
extension FIRStorageReference {

    /**
     store **UIImage as JPEG**
     */
    func rx_putJPEG(image: UIImage, compressionQuality: CGFloat = 1) -> Observable<FIRStorageMetadata> {
        
        guard let imageData = UIImageJPEGRepresentation(image, compressionQuality) else {
            return Observable.error(FirebaseError.Custom(message: "conversion error"))
        }
        
        let metadata = FIRStorageMetadata()
        metadata.contentType = "image/jpeg"
        // metadata.cacheControl = "public,max-age=300"
        
        return rx_putData(withData: imageData, metadata: metadata)
    }
    
    /**
     store **NSData**
     */
    func rx_putData(withData withData: NSData, metadata: FIRStorageMetadata? = nil) -> Observable<FIRStorageMetadata> {
        
        return Observable.create { (observer : AnyObserver<FIRStorageMetadata>) -> Disposable in
            
            let uploadTask = self.putData(withData, metadata: metadata) { metadata, error in
                    
                    if let error = error {
                        observer.onError(FirebaseError.Custom(message: error.localizedDescription))
                    } else if let metadata = metadata {
                        observer.onNext(metadata)
                        observer.onCompleted()
                    } else {
                        observer.onError(FirebaseError.Custom(message: "storage: no metadata"))
                    }
            }
            
            return AnonymousDisposable {
                uploadTask.cancel()
            }
        }
    }
    
    /**
     download **NSData**
     */
    func rx_downloadData(maxSize: Int64 = 1024 * 1024) -> Observable<NSData> {
        
        return Observable.create { (observer : AnyObserver<NSData>) -> Disposable in
            
            let downloadTask = self.dataWithMaxSize(maxSize) { data, error -> Void in
                    if let error = error {
                        observer.onError(FirebaseError.Custom(message: error.localizedDescription))
                    } else if let data = data {
                        observer.onNext(data)
                        observer.onCompleted()
                    } else {
                        observer.onError(FirebaseError.Custom(message: "storage: no data"))
                    }
                }
            
            return AnonymousDisposable {
                downloadTask.cancel()
            }
        }
    }
    
    /**
     download **UIImage**
     */
    func rx_downloadImage() -> Observable<UIImage> {
        
        return rx_downloadData().map({ data -> UIImage in
            
            guard let image = UIImage(data: data) else {
                throw FirebaseError.Custom(message: "conversion error")
            }
            
            return image
        })
    }
    
    /**
     download to **local NSURL**
     */
    func rx_downloadTo(url url: NSURL) -> Observable<Void> {
        
        return Observable.create { (observer : AnyObserver<Void>) -> Disposable in
            
            /*
            let paths = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory,
                NSSearchPathDomainMask.UserDomainMask, true)
            let documentsDirectory = paths[0]
            let filePath = "file:\(documentsDirectory)/myimage.jpg"
            let storagePath = NSUserDefaults.standardUserDefaults().objectForKey("storagePath") as! String
            */
            
            // NSURL.fileURLWithPath("file:\(filename)")
            
            let downloadTask = self.writeToFile(url, completion: { url, error in
                    if let error = error {
                        observer.onError(FirebaseError.Custom(message: error.localizedDescription))
                    } else if let _ = url {
                        observer.onNext()
                        observer.onCompleted()
                    } else {
                        observer.onError(FirebaseError.DownloadError)
                    }
                })
            
            return AnonymousDisposable {
                downloadTask.cancel()
            }
        }
    }
    
    
}


// ============================================================================
// MARK: DATABASE
// ============================================================================
extension FIRDatabaseReference {
    
    /**
     set Dictionary to **`self`** or **`childByAutoId()`**
     */
    func rx_setValue(object: AnyObject, autoId: Bool = false) -> Observable<Void> {
        
        return Observable.create { (observer : AnyObserver<Void>) -> Disposable in
            
            let reference = autoId ? self.childByAutoId() : self
            
            reference.setValue(object, withCompletionBlock: { (error, _) in
                    if let error = error {
                        observer.onError(FirebaseError.Custom(message: error.localizedDescription))
                    } else {
                        observer.onNext()
                        observer.onCompleted()
                    }
                })
            
            return NopDisposable.instance
        }
    }
    
    /**
     observe event
     */
    func rx_observe(eventType: FIRDataEventType = .Value) -> Observable<FIRDataSnapshot> {
        
        return Observable.create({ observer in
            
            let observer = self.observeEventType(eventType, withBlock: { data in
                    observer.onNext(data)
                    }, withCancelBlock: { error in
                        observer.onError(FirebaseError.Custom(message: error.localizedDescription))
                })
            
            return AnonymousDisposable{
                self.removeObserverWithHandle(observer)
            }
        })
    }
    
    /**
     observe single event
     */
    func rx_observeSingleEventOfType(eventType: FIRDataEventType = .Value) -> Observable<FIRDataSnapshot> {
        
        return Observable.create({ observer in
            
            self.observeSingleEventOfType(eventType, withBlock: { data in
                observer.onNext(data)
                observer.onCompleted()
                }, withCancelBlock: { error in
                    observer.onError(FirebaseError.Custom(message: error.localizedDescription))
            })
            
            return NopDisposable.instance
        })
    }
}


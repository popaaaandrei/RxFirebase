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
public enum FirebaseError: Error, CustomStringConvertible {
    
    case NotAuthenticated
    case AuthDataNotValid
    case PermissionDenied
    case DownloadError
    case Custom(message: String)
    
    
    public var description: String {
        switch self {
        case .NotAuthenticated:
            return "Not authenticated"
        case .AuthDataNotValid:
            return "Authentication data is not valid"
        case .PermissionDenied:
            return "permission denied"
        case .DownloadError:
            return "download error"
        case .Custom(let message):
            return "\(message)"
        }
    }
}



// ============================================================================
// MARK: Firebase
// ============================================================================
class Firebase {
    
    static let instance = Firebase()
    
    let rx_user = ReplaySubject<User>.create(bufferSize: 1)
    let rx_error = PublishSubject<String>()
    
    // private
    private let disposeBag = DisposeBag()
    var database : DatabaseReference?
    var storage : StorageReference?
    
    
    private init() {
        // firebase
        FirebaseApp.configure()
        
        database = Database.database().reference()
        storage = Storage.storage().reference()
    }
    
    var clientID : String? {
        return FirebaseApp.app()?.options.clientID
    }
    var userID : String? {
        return Auth.auth().currentUser?.uid
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            rx_user.onNext(Auth.auth().currentUser!) //user will be nill can check on call back
        } catch let signOutError as NSError {
            rx_error.onNext(signOutError.localizedDescription)
        }
    }
}



// ============================================================================
// MARK: AUTH
// ============================================================================
extension Firebase {
    func rx_currentUser() -> Observable<User> {
        
        if let user = Auth.auth().currentUser {
            return Observable.just(user)
        }
        else {
            return Observable.error(FirebaseError.NotAuthenticated)
        }
    }
    
    func rx_authStateDidChange() -> Observable<Auth> {
        var authStateListenerHandle: AuthStateDidChangeListenerHandle?
        return Observable.create { (observer : AnyObserver<Auth>) -> Disposable in
            
            let listener = Auth.auth().addStateDidChangeListener { auth, _ in
                observer.onNext(auth)
            }
            return Disposables.create()
            
        }
        
    }
    
    func rx_signInWithEmail(email: String, password: String) -> Observable<User> {
        
        guard email.characters.count > 0 && password.characters.count > 0 else {
            return Observable.error(FirebaseError.AuthDataNotValid)
        }
        
        return Observable.create { (observer : AnyObserver<User>) -> Disposable in
            
            Auth.auth().signIn(withEmail: email, password: password) { user, error in
                if let error = error {
                    observer.onError(error)
                }
                if let user = user {
                    observer.onNext(user)
                    observer.onCompleted()
                }
            }
            
            return Disposables.create()
        }
    }
    
    func rx_signInWithCredential(credential: AuthCredential) -> Observable<User> {
        
        return Observable.create { (observer : AnyObserver<User>) -> Disposable in
            
            Auth.auth().signIn(with: credential, completion: { user, error in
                if let error = error {
                    observer.onError(error)
                }
                if let user = user {
                    observer.onNext(user)
                    observer.onCompleted()
                }
            })
            
            return Disposables.create()
        }
    }
    
    func rx_sendPasswordResetWithEmail(email: String) -> Observable<Void> {
        
        return Observable.create { (observer : AnyObserver<Void>) -> Disposable in
            
            Auth.auth().sendPasswordReset(withEmail: email) { error in
                if let error = error {
                    observer.onError(FirebaseError.Custom(message: error.localizedDescription))
                } else {
                    observer.onNext()
                    observer.onCompleted()
                }
            }
            
            return Disposables.create()
        }
    }
    
    func rx_createUser(email: String, password: String) -> Observable<User> {
        
        guard email.characters.count > 0 && password.characters.count > 0 else {
            return Observable.error(FirebaseError.AuthDataNotValid)
        }
        
        return Observable.create { (observer : AnyObserver<User>) -> Disposable in
            
            Auth.auth().createUser(withEmail: email, password: password) { user, error in
                if let error = error {
                    observer.onError(error)
                }
                if let user = user {
                    observer.onNext(user)
                    observer.onCompleted()
                }
            }
            
            return Disposables.create()
        }
    }
    
    func rx_publish(object: AnyObject, atPath: String) -> Observable<Void> {
        
        guard let database = Firebase.instance.database else {
            return Observable.error(FirebaseError.PermissionDenied)
        }
        
        return database
            .root
            .child(atPath)
            .rx_setValue(object: object)
    }
    
}

// ============================================================================
// MARK: STORAGE
// ============================================================================
extension StorageReference {
    
    /**
     store **UIImage as JPEG**
     */
    func rx_putJPEG(image: UIImage, compressionQuality: CGFloat = 1) -> Observable<StorageMetadata> {
        
        guard let imageData = UIImageJPEGRepresentation(image, compressionQuality) else {
            return Observable.error(FirebaseError.Custom(message: "conversion error"))
        }
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        //metadata.cacheControl = "public,max-age=300"
        
        return rx_putData(withData: imageData as NSData, metadata: metadata)
    }
    
    /**
     store **NSData**
     */
    func rx_putData(withData: NSData, metadata: StorageMetadata? = nil) -> Observable<StorageMetadata> {
        
        return Observable.create { (observer : AnyObserver<StorageMetadata>) -> Disposable in
            
            let uploadTask = self.putData(withData as Data, metadata: metadata) { metadata, error in
                
                if let error = error {
                    observer.onError(FirebaseError.Custom(message: error.localizedDescription))
                } else if let metadata = metadata {
                    observer.onNext(metadata)
                    observer.onCompleted()
                } else {
                    observer.onError(FirebaseError.Custom(message: "storage: no metadata"))
                }
            }
            
            return Disposables.create{
                uploadTask.cancel()
            }
        }
    }
    
    /**
     download **NSData**
     */
    func rx_downloadData(maxSize: Int64 = 1024 * 1024) -> Observable<NSData> {
        
        return Observable.create { (observer : AnyObserver<NSData>) -> Disposable in
            
            let downloadTask = self.getData(maxSize: maxSize) { data, error -> Void in
                if let error = error {
                    observer.onError(FirebaseError.Custom(message: error.localizedDescription))
                } else if let data = data {
                    observer.onNext(data as NSData)
                    observer.onCompleted()
                } else {
                    observer.onError(FirebaseError.Custom(message: "storage: no data"))
                }
            }
            
            return Disposables.create {
                downloadTask.cancel()
            }
        }
    }
    
    /**
     download **UIImage**
     */
    func rx_downloadImage() -> Observable<UIImage> {
        
        return rx_downloadData().map({ data -> UIImage in
            
            guard let image = UIImage(data: data as Data) else {
                throw FirebaseError.Custom(message: "conversion error")
            }
            
            return image
        })
    }
    
    /**
     download to **local NSURL**
     */
    func rx_downloadTo(url: NSURL) -> Observable<Void> {
        
        return Observable.create { (observer : AnyObserver<Void>) -> Disposable in
            
            /*
             let paths = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory,
             NSSearchPathDomainMask.UserDomainMask, true)
             let documentsDirectory = paths[0]
             let filePath = "file:\(documentsDirectory)/myimage.jpg"
             let storagePath = NSUserDefaults.standardUserDefaults().objectForKey("storagePath") as! String
             */
            
            // NSURL.fileURLWithPath("file:\(filename)")
            
            let downloadTask = self.write(toFile: url as URL, completion: { url, error in
                if let error = error {
                    observer.onError(FirebaseError.Custom(message: error.localizedDescription))
                } else if let _ = url {
                    observer.onNext()
                    observer.onCompleted()
                } else {
                    observer.onError(FirebaseError.DownloadError)
                }
            })
            
            return Disposables.create{
                downloadTask.cancel()
            }
        }
    }
    
    
}


// ============================================================================
// MARK: DATABASE
// ============================================================================
extension DatabaseReference {
    
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
            
            return Disposables.create()
        }
    }
    
    /**
     observe event
     */
    func rx_observe(eventType: DataEventType) -> Observable<DataSnapshot> {
        
        return Observable.create({ observer in
            
            let observer = self.observe(eventType, with: { data in
                observer.onNext(data)
            }, withCancel: { error in
                observer.onError(FirebaseError.Custom(message: error.localizedDescription))
            })
            
            return Disposables.create{
                
            }
        })
    }
    
    /**
     observe single event
     */
    func rx_observeSingleEventOfType(eventType: DataEventType = .value) -> Observable<DataSnapshot> {
        
        return Observable.create({ observer in
            
            self.observeSingleEvent(of: eventType, with: { data in
                observer.onNext(data)
                observer.onCompleted()
            }, withCancel: { error in
                observer.onError(FirebaseError.Custom(message: error.localizedDescription))
            })
            
            return Disposables.create()
        })
    }
}


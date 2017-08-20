//
//  Firebase.swift
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
    
    case notAuthenticated
    case authDataNotValid
    case permission
    case download
    case custom(message: String)
    
    
    public var description: String {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .authDataNotValid:
            return "Authentication data is not valid"
        case .permission:
            return "permission denied"
        case .download:
            return "download error"
        case .custom(let message):
            return "\(message)"
        }
    }
}



// ============================================================================
// MARK: Firebase
// ============================================================================
class Firebase {
    
    static let instance = Firebase()
    
    
    /// right now only catches signOut errors
    let rx_error = PublishSubject<String>()
    
    // private
    private let disposeBag = DisposeBag()
    var database : DatabaseReference?
    var storage : StorageReference?
    
    
    private init() {
        FirebaseApp.configure()
        database = Database.database().reference()
        storage = Storage.storage().reference()
    }
    
    /// current client id
    var clientID : String? {
        return FirebaseApp.app()?.options.clientID
    }
    
    /// current user id
    var userID : String? {
        return Auth.auth().currentUser?.uid
    }
    
    /// current user
    var user: User? {
        return Auth.auth().currentUser
    }
    
    /// signOut of Firebase, errors published in `rx_error`
    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch let signOutError as NSError {
            rx_error.onNext(signOutError.localizedDescription)
        }
    }
}



// ============================================================================
// MARK: AUTH
// ============================================================================
extension Firebase {
    
    
    /// exposes the changes in Auth and User
    func rx_authStateDidChange() -> Observable<(Auth, User?)> {
        
        return Observable.create { (observer : AnyObserver<(Auth, User?)>) -> Disposable in
            
            let listener = Auth.auth().addStateDidChangeListener { auth, user in
                observer.onNext((auth, user))
            }
            
            return Disposables.create {
                Auth.auth().removeStateDidChangeListener(listener)
            }
        }
        
    }
    
    func rx_signInWithEmail(email: String, password: String) -> Observable<User> {
        
        guard email.characters.count > 0 && password.characters.count > 0 else {
            return Observable.error(FirebaseError.authDataNotValid)
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
                    observer.onError(FirebaseError.custom(message: error.localizedDescription))
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
            return Observable.error(FirebaseError.authDataNotValid)
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
            return Observable.error(FirebaseError.permission)
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
            return Observable.error(FirebaseError.custom(message: "conversion error"))
        }
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        //metadata.cacheControl = "public,max-age=300"
        
        return rx_putData(withData: imageData, metadata: metadata)
    }
    
    /**
     store **Data**
     */
    func rx_putData(withData: Data, metadata: StorageMetadata? = nil) -> Observable<StorageMetadata> {
        
        return Observable.create { (observer : AnyObserver<StorageMetadata>) -> Disposable in
            
            let uploadTask = self.putData(withData, metadata: metadata) { metadata, error in
                
                if let error = error {
                    observer.onError(FirebaseError.custom(message: error.localizedDescription))
                } else if let metadata = metadata {
                    observer.onNext(metadata)
                    observer.onCompleted()
                } else {
                    observer.onError(FirebaseError.custom(message: "storage: no metadata"))
                }
            }
            
            return Disposables.create {
                uploadTask.cancel()
            }
        }
    }
    
    /**
     download **Data**
     */
    func rx_downloadData(maxSize: Int64 = 1024 * 1024) -> Observable<Data> {
        
        return Observable.create { (observer : AnyObserver<Data>) -> Disposable in
            
            let downloadTask = self.getData(maxSize: maxSize) { data, error -> Void in
                if let error = error {
                    observer.onError(FirebaseError.custom(message: error.localizedDescription))
                } else if let data = data {
                    observer.onNext(data)
                    observer.onCompleted()
                } else {
                    observer.onError(FirebaseError.custom(message: "storage: no data"))
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
            
            guard let image = UIImage(data: data) else {
                throw FirebaseError.custom(message: "image conversion error")
            }
            
            return image
        })
    }
    
    /**
     download to **local URL**
     */
    func rx_downloadTo(url: URL) -> Observable<Void> {
        
        return Observable.create { (observer : AnyObserver<Void>) -> Disposable in
            
            let downloadTask = self.write(toFile: url, completion: { url, error in
                if let error = error {
                    observer.onError(FirebaseError.custom(message: error.localizedDescription))
                } else if let _ = url {
                    observer.onNext()
                    observer.onCompleted()
                } else {
                    observer.onError(FirebaseError.download)
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
                    observer.onError(FirebaseError.custom(message: error.localizedDescription))
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
    func rx_observe(eventType: DataEventType = .value) -> Observable<DataSnapshot> {
        
        return Observable.create({ observer in
            
            let observer = self.observe(eventType, with: { data in
                observer.onNext(data)
            }, withCancel: { error in
                observer.onError(FirebaseError.custom(message: error.localizedDescription))
            })
            
            return Disposables.create {
                self.removeObserver(withHandle: observer)
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
                observer.onError(FirebaseError.custom(message: error.localizedDescription))
            })
            
            return Disposables.create()
        })
    }
}



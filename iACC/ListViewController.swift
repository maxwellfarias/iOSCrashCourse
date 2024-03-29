//
// Copyright © Essential Developer. All rights reserved.
//

import UIKit

class ListViewController: UITableViewController {
    var items = [ItemViewModel]()
    
    var retryCount = 0
    var maxRetryCount = 0
    var shouldRetry = false
    
    var longDateStyle = false
    
    var fromReceivedTransfersScreen = false
    var fromSentTransfersScreen = false
    var fromCardsScreen = false
    var fromFriendsScreen = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        
        if fromFriendsScreen {
            shouldRetry = true
            maxRetryCount = 2
            
            title = "Friends"
            
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addFriend))
            
        } else if fromCardsScreen {
            shouldRetry = false
            
            title = "Cards"
            
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addCard))
            
        } else if fromSentTransfersScreen {
            shouldRetry = true
            maxRetryCount = 1
            longDateStyle = true
            
            navigationItem.title = "Sent"
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Send", style: .done, target: self, action: #selector(sendMoney))
            
        } else if fromReceivedTransfersScreen {
            shouldRetry = true
            maxRetryCount = 1
            longDateStyle = false
            
            navigationItem.title = "Received"
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Request", style: .done, target: self, action: #selector(requestMoney))
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if tableView.numberOfRows(inSection: 0) == 0 {
            refresh()
        }
    }
    
    @objc private func refresh() {
        refreshControl?.beginRefreshing()
        if fromFriendsScreen {
            FriendsAPI.shared.loadFriends { [weak self] result in
                DispatchQueue.mainAsyncIfNeeded {
                    self?.handleAPIResult(result)
                }
            }
        } else if fromCardsScreen {
            CardAPI.shared.loadCards { [weak self] result in
                DispatchQueue.mainAsyncIfNeeded {
                    self?.handleAPIResult(result)
                }
            }
        } else if fromSentTransfersScreen || fromReceivedTransfersScreen {
            TransfersAPI.shared.loadTransfers { [weak self] result in
                DispatchQueue.mainAsyncIfNeeded {
                    self?.handleAPIResult(result)
                }
            }
        } else {
            fatalError("unknown context")
        }
    }
    
    private func handleAPIResult<T>(_ result: Result<[T], Error>) {
        switch result {
        case let .success(items):
            if fromFriendsScreen && User.shared?.isPremium == true {
                (UIApplication.shared.connectedScenes.first?.delegate as! SceneDelegate).cache.save(items as! [Friend])
            }
            self.retryCount = 0
            
            var filteredItems = items as [Any]
            if let transfers = items as? [Transfer] {
                if fromSentTransfersScreen {
                    filteredItems = transfers.filter(\.isSender)
                } else {
                    filteredItems = transfers.filter { !$0.isSender }
                }
            }
            
            self.items = filteredItems.map({ item in
                 ItemViewModel(item, longDateStyle: longDateStyle) { [weak self] in
                    if let friend = item as? Friend {
                        self?.select(friend: friend)
                    } else if let card = item as? Card {
                        self?.select(card: card)
                    } else if let transfer = item as? Transfer {
                        self?.select(transfer: transfer)
                    } else {
                        fatalError("unknown item: \(item)")
                    }
                }
            })
            self.refreshControl?.endRefreshing()
            self.tableView.reloadData()
            
        case let .failure(error):
            if shouldRetry && retryCount < maxRetryCount {
                retryCount += 1
                
                refresh()
                return
            }
            
            retryCount = 0
            
            if fromFriendsScreen && User.shared?.isPremium == true {
                (UIApplication.shared.connectedScenes.first?.delegate as! SceneDelegate).cache.loadFriends { [weak self] result in
                    DispatchQueue.mainAsyncIfNeeded {
                        switch result {
                        case let .success(items):
                            self?.items = items.map({ item in
                                ItemViewModel(item) { [weak self] in
                                    self?.select(friend: item)
                                }
                            })
                            self?.tableView.reloadData()
                            
                        case let .failure(error):
                            self?.show(error: error)
                        }
                        self?.refreshControl?.endRefreshing()
                    }
                }
            } else {
                show(error: error)
                self.refreshControl?.endRefreshing()
            }
        }
    }
    
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "ItemCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "ItemCell")
        cell.configure(item)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        item.select()
    }
}

struct ItemViewModel {
    let title: String
    let subtitle: String
    //Recebe a logica de chamar uma outra tela
    let select: () -> Void
    
    init (_ item: Any, longDateStyle: Bool, selection: @escaping () -> Void) {
        if let friend = item as? Friend {
            self.init(friend, selection: selection)
        } else if let card = item as? Card {
            self.init(card, selection: selection)
        } else if let transfer = item as? Transfer {
            self.init(transfer, longDateStyle: longDateStyle, selection: selection)
        } else {
            fatalError("unknown item: \(item)")
        }
    }
}

extension ItemViewModel {
    init(_ friend: Friend, selection: @escaping () -> Void) {
        title = friend.name
        subtitle = friend.phone
        select = selection
    }
}

extension ItemViewModel {
    init(_ card: Card, selection: @escaping () -> Void) {
        title = card.number
        subtitle = card.holder
        select = selection
    }
}

extension ItemViewModel {
    init(_ transfer: Transfer, longDateStyle: Bool, selection: @escaping () -> Void) {
        let numberFormatter = Formatters.number
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = transfer.currencyCode
        
        let amount = numberFormatter.string(from: transfer.amount as NSNumber)!
        title = "\(amount) • \(transfer.description)"
        
        let dateFormatter = Formatters.date
        if longDateStyle {
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .short
            subtitle = "Sent to: \(transfer.recipient) on \(dateFormatter.string(from: transfer.date))"
        } else {
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            subtitle = "Received from: \(transfer.sender) on \(dateFormatter.string(from: transfer.date))"
        }
        select = selection
    }
}
extension UITableViewCell {
    func configure(_ vm: ItemViewModel) {
        textLabel?.text = vm.title
        detailTextLabel?.text = vm.subtitle
    }
}

extension UIViewController {
    func select(friend: Friend) {
        let vc = FriendDetailsViewController()
        vc.friend = friend
        show(vc, sender: self)
    }
    
    func select(card: Card) {
        let vc = CardDetailsViewController()
        vc.card = card
        show(vc, sender: self)
    }
    
    func select(transfer: Transfer) {
        let vc = TransferDetailsViewController()
        vc.transfer = transfer
        show(vc, sender: self)
    }
}

extension UIViewController {
    @objc func addCard() {
        show(AddCardViewController(), sender: self)
    }
    
    @objc func addFriend() {
        show(AddFriendViewController(), sender: self)
    }
    
    @objc func sendMoney() {
        show(SendMoneyViewController(), sender: self)
    }
    
    @objc func requestMoney() {
        show(RequestMoneyViewController(), sender: self)
    }
    
    func show(error: Error) {
        let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Ok", style: .default))
        showDetailViewController(alert, sender: self)
    }
}
